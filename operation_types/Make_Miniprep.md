# Make Miniprep

Purifies overnight and creates an unverified plasmid stock for later use.

The overnight is purified by the technician, an the end product is an unverified plasmid stock, which will be sent out for sequencing. The overnight is stored in the fridge, for use later in **Make Glycerol Stock**.

Ran the day after **Make Overnight Suspension** and is a precursor to **Send to Sequencing**.
### Inputs


- **Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "TB Overnight of Plasmid")'>TB Overnight of Plasmid</a>



### Outputs


- **Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
# frozen_string_literal: true

def precondition(_op)
  true
end

```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

needs 'Cloning Libs/Cloning'
needs 'Standard Libs/Feedback'

class Protocol
  include Feedback
  include Cloning

  def main
    # Find all overnights and take them
    operations.retrieve

    # Verify whether each overnight has growth
    verify_growth = show do
      title 'Check if overnights have growth'
      note 'Choose No for the overnight that does not have growth and throw them away or put in the clean station.'
      operations.each do |op|
        item_id = op.input('Plasmid').child_item.id
        select %w[Yes No], var: item_id.to_s, label: "Does tube #{item_id} have growth?"
      end
    end

    # if no growth, delete the overnight
    operations.each do |op|
      item = op.input('Plasmid').child_item
      if verify_growth[item.id.to_s.to_sym] == 'No'
        item.mark_as_deleted
        op.error :no_growth, 'The overnight has no growth.'
      end
    end

    operations.running.make

    # transfer each overnight into 1.5 mL tube
    show do
      title 'Transfer Overnights into 1.5 mL Tubes'
      note "Grab #{operations.length} 1.5 mL tubes and label from 1 to #{operations.length}"
      note 'Transfer 1.5 mL of the overnight into the corresponding 1.5 mL tube.'
      index = 0
      table operations.start_table
                      .input_item('Plasmid')
                      .custom_column(heading: 'Tube Number') { index += 1 }
                      .end_table
    end

    # Spin down cells and remove supernatant
    show do
      title 'Spin down the cells'
      check 'Spin at 5,800 xg for 2 minutes, make sure to balance.'
      check 'Remove the supernatant. Pour off the supernatant into liquid waste, being sure not to upset the pellet. Pipette out the residual supernatant.'
    end

    # Resuspend in P1, P2, N3
    show do
      title 'Resuspend in P1, P2, N3'
      check 'Add 250 uL of P1 into each tube and vortex strongly to resuspend.'
      check 'Add 250 uL of P2 and gently invert 5-10 times to mix, tube contents should turn blue.'
      check 'Pipette 350 uL of N3 into each tube and gently invert 5-10 times to mix. Tube contents should turn colorless.'
      warning 'Time between adding P2 and N3 should be minimized. Cells should not be exposed to active P2 for more than 5 minutes'
    end

    # Centrifuge and add to miniprep columns
    show do
      title 'Centrifuge and add to columns'
      check 'Spin tubes at 17,000 xg for 10 minutes'
      warning 'Make sure to balance the centrifuge.'
      check "Grab #{operations.running.length} blue miniprep spin columns and label with 1 to #{operations.running.length}."
      check 'Remove the tubes from centrifuge and carefully pipette the supernatant (up to 750 uL) into the same labeled columns.'
      warning 'Be careful not to disturb the pellet.'
      check 'Discard the used 1.5 mL tubes into waste bin.'
    end

    # Spin and wash
    show do
      title 'Spin and Wash'
      check 'Spin all columns at 17,000 xg for 1 minute. Make sure to balance.'
      check 'Remove the columns from the centrifuge and discard the flow through into a liquid waste container'
      check 'Add 750 uL of PE buffer to each column. Make sure the PE bottle that you are using has ethanol added!'
      check 'Spin the columns at 17,000 xg for 1 minute'
      check 'Remove the columns from the centrifuge and discard the flow through into a liquid waste container.'
      check 'Perform a final spin: spin all columns at 17,000 xg for 1 minute.'
    end

    # Elute w water
    show do
      title 'Elute with water'
      check "Grab  #{operations.length} new 1.5 mL tubes and label top of the tube with 1 to  #{operations.length}."
      check 'Remove the columns from the centrifuge'
      check 'Inidividually take each column out of the flowthrough collector and put it into the labeled 1.5 mL tube with the same number, discard the flowthrough collector.'
      warning 'For this step, use a new pipette tip for each sample to avoid cross contamination'
      check 'Pipette 50 uL of water into the CENTER of each column'
      check 'Let the tubes sit on the bench for 2 minutes'
      check 'Spin the columns at 17,000 xg for 1 minute'
      check 'Remove the tubes and discard the columns'
    end

    # Relabel tubes w output ids
    show do
      title 'Relabel Tubes'
      note 'Relabel each tube with the corresponding item ID'
      index = 0
      table operations.start_table
                      .custom_column(heading: 'Tube Number') { index += 1 }
                      .output_item('Plasmid')
                      .end_table
    end

    # nanodrop and get concentration
    show do
      title 'Nanodrop and Enter Concentration'
      note 'Nanodrop each plasmid and enter the concentration below'
      table operations.start_table
        .output_item('Plasmid')
                      .get(:concentration, type: 'number', heading: 'Concentration', default: 200)
                      .end_table
    end

    # set concentration of plasmid stock and change location of overnights
    operations.running.each do |op|
      op.set_output_data 'Plasmid', :concentration, op.temporary[:concentration]
      op.set_output_data 'Plasmid', :from, op.input('Plasmid').item.id
      op.plan.associate "overnight_#{op.input('Plasmid').sample.id}", op.input('Plasmid').item.id
      op.plan.associate :plasmid, op.output('Plasmid').item.id
      op.input('Plasmid').child_item.store

      pass_data 'sequencing results', 'sequence_verified', from: op.input('Plasmid').item, to: op.output('Plasmid').item
    end

    operations.running.store

    get_protocol_feedback

    {}
  end
end

```
