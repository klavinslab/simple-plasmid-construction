# Run Gel

Runs a selected gel through gel electrophoresis.

A 50 mL 1 percent Agarose Gel is loaded with the input samples in preparation for gel electrophoresis. 
The gel is then run at 100 Volts for 40 minutes. This operation type creates "Pour Gel" and
"Extract Fragment" operation associations for later use.

Ran after *Pour Gel* and is a precursor to *Extract Fragment*.
### Inputs


- **Fragment** [F]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Stripwell")'>Stripwell</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Stripwell of Digested Plasmid")'>Stripwell of Digested Plasmid</a>

- **Gel** [L]  Part of collection



### Outputs


- **Fragment** [F]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "50 mL 0.8 Percent Agarose Gel in Gel Box")'>50 mL 0.8 Percent Agarose Gel in Gel Box</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "50 mL 0.8 Percent Agarose Gel in Gel Box")'>50 mL 0.8 Percent Agarose Gel in Gel Box</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
    true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

# TO DO: 100 BP LADDER ONLY WHEN A FRAGMENT LESS THAN 500 BP ONLY
needs 'Standard Libs/Feedback'
class Protocol
  include Feedback
  def main
    operations.retrieve interactive: false

    # manually set input and outputs so that they ascend in parrellel for id, row, column
    # also returns sorted operationslist
    sorted_ops = align_input_and_output_indicies operations
    operations = sorted_ops

    gels = operations.map { |op| op.input('Gel').collection }.uniq
    stripwells = operations.map { |op| op.input('Fragment').collection }.uniq.sort_by(&:id)

    # Find a ladder
    ladder_100 = Sample.find_by_name('100 bp Ladder')
    ladder_1k = Sample.find_by_name('1 kb Ladder')
    dye = Sample.find_by_name('6X Loading Dye')
    items = [ladder_100.in('Ladder Aliquot').first,
             ladder_1k.in('Ladder Aliquot').first,
             Item.where(sample_id: dye.id).reject(&:deleted?).first]

    take items + gels.collect { |i| Item.find_by_id(i.id) } + stripwells.collect { |i| Item.find_by_id(i.id) }, interactive: true

    setup_power_supply

    setup_gel_box

    add_dye stripwells

    # ONLY DO 100 BP IF THERE IS FRAGMENT W LENGTH < 500 BP
    add_ladders_to_gel gels, ladder_1k, ladder_100

    # TO DO: Fix loading if ladders exist
    transfer_result_to_lane

    start_electrophoresis

    discard_stripwells

    release items, interactive: true

    set_timer
    get_protocol_feedback
    {}
  end

  # Change the input and output field values so that their item ids, row, and column
  # are all strictly ascending (in that sort order). The mapping from input->output
  # is manually made to enforce this parrellel
  def align_input_and_output_indicies(ops)
    # Sort operations by gels and columns (these can get out of order from PCR)
    ops.sort! do |op1, op2|
      fv1 = op1.input('Fragment')
      fv2 = op2.input('Fragment')
      [fv1.item.id, fv1.column] <=> [fv2.item.id, fv2.column]
    end

    gels = ops.map { |op| op.input('Gel').collection }.uniq.sort_by(&:id)
    gel_size = gels.first.object_type.rows * gels.first.object_type.columns
    gel_columns = gels.first.object_type.columns

    # spots already taken up by the ladder in gel:
    ###############
    # 1 1 0 0 0 0 #
    # 1 1 0 0 0 0 #
    ###############
    size_adjusted_for_lader = gel_size - 4
    columns_adjusted_for_ladder = gel_columns - 2
    column_start_adjusted_for_ladder = 2

    # associate operations with new gel, row & column
    ops.each_with_index do |op, idx|
      gel_idx = idx / size_adjusted_for_lader
      lane = idx % size_adjusted_for_lader
      row = lane / columns_adjusted_for_ladder
      column = (lane % columns_adjusted_for_ladder) + column_start_adjusted_for_ladder

      gel_fv = op.input('Gel')
      gel_fv.set collection: gels[gel_idx]
      gel_fv.row = row
      gel_fv.column = column
      gel_fv.save
      # show { note "op #{idx}: col: #{op.input("Gel").collection.id}, row: #{op.input("Gel").row}, column: #{op.input("Gel").column}" }
    end

    # Don't use generic operations.make
    ops.each do |op|
      op.output('Fragment').make_part(
        op.input('Gel').collection,
        op.input('Gel').row,
        op.input('Gel').column
      )
    end
    ops
  end

  # This method tells the technician to set up the power supply.
  def setup_power_supply
    show do
      title 'Set up the power supply'

      note  'In the gel room, obtain a power supply and set it to 80 V and with a 40 minute timer.'
      note  'Attach the electrodes of an appropriate gel box lid to the power supply.'

      image 'Items/gel_power_settings.JPG'
    end
  end

  # This method tells the technician to set up the power supply.
  def setup_gel_box
    show do
      title 'Set up the gel box(s).'

      check 'Remove the casting tray(s) (with gel(s)) and place it(them) on the bench.'
      check 'Using the graduated cylinder, fill the gel box(s) with 200 mL of 1X TAE. TAE should just cover the center of the gel box(s).'
      check 'With the gel box(s) electrodes facing away from you, place the casting tray(s) (with gel(s)) back in the gel box(s). The top lane(s) should be on your left, as the DNA will move to the right.'
      check 'Using the graduated cylinder, add 50 mL of 1X TAE so that the surface of the gel is covered.'
      check 'Remove the comb(s) and place them in the appropriate box(s).'
      check 'Put the graduated cylinder back.'

      image 'Items/gel_fill_TAE_to_line.JPG'
    end
  end

  # This method tells the technician to transfer PCR results into their indicated gel lanes.
  def transfer_result_to_lane
    show do
      title 'Transfer 50 uL of each PCR result into indicated gel lane'
      note 'Transfer samples from each stripwell to the gel(s) according to the following table:'
      table operations.reject(&:virtual?).sort { |op1, op2| op1.input('Fragment').item.id <=> op2.input('Fragment').item.id }.extend(OperationList).start_table
                      .input_collection('Fragment', heading: 'Stripwell')
                      .custom_column(heading: 'Well Number') { |op| (op.input('Fragment').column + 1) }
                      .input_collection('Gel', heading: 'Gel')
                      .custom_column(heading: 'Gel Row') { |op| (op.input('Gel').row + 1) }
                      .custom_column(heading: 'Gel Column', checkable: true) { |op| (op.input('Gel').column + 1) }
                      .end_table
    end
  end

  # This method tells the technician to start electrophoresis
  def start_electrophoresis
    show do
      title 'Start Electrophoresis'
      note 'Carefully attach the gel box lid(s) to the gel box(es). Attach the red electrode to the red terminal of the power supply, and the black electrode to the neighboring black terminal. Hit the start button on the gel boxes.'
      note 'Make sure the power supply is not erroring (no E* messages) and that there are bubbles emerging from the platinum wires in the bottom corners of the gel box.'
      image 'Items/gel_check_for_bubbles.JPG'
    end
  end

  # Tells the technician to discard stripwells
  def discard_stripwells
    show do
      title 'Discard Stripwells'
      note 'Discard all the empty stripwells'
      operations.each do |op|
        if !op.input('Fragment').item.nil?
          op.input('Fragment').item.mark_as_deleted
        else
          show do
            note 'is nil. Cannot discard.' # {op.input("Fragment").item.id}
          end
        end
      end
    end
  end

  # Tells the technician to set a timer.
  def set_timer
    show do
      title 'Set a timer'

      check 'When you get back to your bench, set a 40 minute timer.'
      check 'When the 40 minute timer is up, grab a lab manager to check on the gel. The lab manager may have you set another timer after checking the gel.'
    end
  end

  # Tells the technician to add dye to each well.
  def add_dye(stripwells)
    show do
      title 'Add Dye to Each Well'
      stripwells.each do |s|
        note "Add 10 uL dye to stripwell #{s.id} from wells #{s.non_empty_string}"
      end
    end
  end

  # This method tells the technician to add ladders to gells.
  def add_ladders_to_gel(gels, ladder_1k, ladder_100)
    gels.each do |gel|
      gel.set 0, 0, ladder_1k.id
      gel.set 0, 1, ladder_100.id
      gel.set 1, 0, ladder_1k.id
      gel.set 1, 1, ladder_100.id
      show do
        title 'Add Ladders to Gel'
        note "Pipette 10 uL of the 1 kb ladder to positions (1,1) and (2,1) of gel #{gel.id}"
        note "Pipette 10 uL of the 100bp ladder to positions (1,2) and (2,2) of gel #{gel.id}"
      end
    end
  end
end

```
