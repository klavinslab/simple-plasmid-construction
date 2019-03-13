# Assemble Plasmid

Assembles Plasmid.

The technician combines the input array of fragments and, using Gibson Assembly, assembles a plasmid. Each Gibson reaction is fixed at a volume of 5 uL, and so the volume of each fragment is calculated using an algorithm that takes in the number of total fragments in the Gibson reaction and the concentration in ng/uL of each individual fragment. The lower bounds for volume is 0.2 uL; if any fragment is below 0.2 uL, or if the overall reaction is greater than 5 uL, the volumes are tweaked for each fragment until the reaction is once more balanced. The reaction is then placed on a 42 F heat block for one hour.

Ran after **Make PCR Fragment** (if the fragment is not already in inventory) and is a precursor to **Transform Cells**.
### Inputs


- **Fragment** [F] (Array) 
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>



### Outputs


- **Assembled Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Gibson Reaction Result")'>Gibson Reaction Result</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
# frozen_string_literal: true

def precondition(operation)
  fragments = operation.input_array('Fragment')
  if fragments.length < 2
    operation.error :more_fragments, "You usually shouldn't do a gibson assembly with less than 2 fragments. Was this intentional?"
  end

  fragments.each do |f|
    next unless f.sample.properties['Length'] == 0.0
    operation.error :need_fragment_length, "Your fragment #{f.sample.name} needs a valid length for assembly."
    return false
  end

  true
end

```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

# Author: Ayesha Saleem
# December 20, 2016

require 'matrix'
needs 'Cloning Libs/Cloning'
needs 'Standard Libs/Feedback'

# TODO: test ensuring volume
# TODO: test replacing fragment stock

# Assemble Plasmid protocol.
#
class Protocol
  include Feedback
  include Cloning

  # this builds a matrix with 1's in the first row
  # the concentration over length (c / l) of the fragment when row = column
  # (with alternating sign) and 0's everywhere else
  def main
    # Check that samples for each input fragment have a non-nil length property.
    operations.each do |op|
      check_fragment_length_present(fragment_array: op.input_array('Fragment'))
    end

    operations.retrieve
    operations.make

    check_concentration(operations, 'Fragment')
    aliquots_needed = find_gibson_batch(operations.running)

    # Go through and pipette fragments into aliquots
    to_discard = []

    # Keep track of fragment stocks to return on errored ops.
    to_return = []

    operations.running.each do |op| # calculate how much of each fragment is needed in aliquot
      fragments = op.input_array('Fragment').items
      tot_f_vol, f_vol = calculate_gibson_volumes(fragments)
      vol_table = create_volume_table(fragments: fragments, fragment_volumes: f_vol)

      # ask tech if there is enough volume
      vol_checking = show do
        title 'Checking Volumes'
        tot_f_vol.each do |id, v|
          select %w[Yes No], var: "v#{id}", label: "Does #{id} have at least #{v} uL?", default: 0
        end
      end

      # find replacements
      replacement = {}

      tot_f_vol.each do |id, v|
        if vol_checking["v#{id}".to_sym] == 'No'
          find_replacements(replacement, to_discard, id, v)
        end
      end

      # associate replacements with operation inputs
      find_replacement = []
      associate_replacements(find_replacement, replacement, op)

      if op.status != 'error'
        # take find_replacement, interactive: true if find_replacement.any?
        check_concentration([op], 'Fragment')

        # feature addition: make an extra column for this table to show whether a p2 pipette is required depending on if vol < 0.5
        if find_replacement.any?
          tot_f_vol, f_vol = calculate_gibson_volumes(fragments)
          vol_table = create_volume_table(
            fragments: fragments, fragment_volumes: f_vol
          )
        end
        load_gibson_reaction(op, vol_table)
        heat_block(operations.running)
      else

        # Keep track of what items need to be returned in the case of an error.
        current_fv = op.input_array('Fragment')
        current_fv.each do |fv|
          to_return.push(fv.item) if fv.item.location != 'deleted'
        end

        show do
          title 'Gibson canceled'
          note 'Sorry it had to be this way. :/'
        end
      end
    end



    # return gibson aliquots
    data = return_gibson_aliquots(aliquots_needed, batch_id_array)
    aliquots_returned = data[:n]

    # updating gibson batches
    gibsons_used = aliquots_needed - aliquots_returned.to_i
    update_gibson_batches(gibsons_used, batch_id_array)

    # return aluminum tube rack, ice block
    return_aluminumTubeRack_and_iceBlock

    # return fragments
    release(to_return, interactive: true)

    operations.store(io: 'input', interactive: true, method: 'boxes')

    if to_discard.any?
      show do
        title 'Discard depleted stocks'
        note "Discard the following stocks: #{to_discard.map(&:id)}"
      end
    end

    get_protocol_feedback
    {}
  end

  def check_fragment_length_present(fragment_array:)
    fragment_array.each do |fragment|
      if fragment.item.sample.properties['Length'].nil?
        op.error(:invalid_length, 'The fragment sample has no length.')
      end
    end
  end

  def find_gibson_batch(operations)
    # TODO: refactor gibson batch finding algorithm, gib_batch instantiation is uneccessarily long
    # determine which batches to grab gibson aliquots from
    gib_batch = Collection.where(object_type_id: ObjectType.find_by_name('Gibson Aliquot Batch').id).where('location != ?', 'deleted').first
    if gib_batch.nil?
      operations.each { |op| op.error :not_enough_gibson, 'There were not enough gibson aliquots to complete the operation.' }
      raise 'not enough gibson'
    end
    batch_id_array = [gib_batch.id]
    total_aliquots = gib_batch.num_samples
    aliquots_needed = operations.length
    i = 0
    while total_aliquots < aliquots_needed
      gib_batch.mark_as_deleted
      i += 1
      gib_batch = Collection.where(object_type_id: ObjectType.find_by_name('Gibson Aliquot Batch').id).where('location != ?', 'deleted').first
      if gib_batch.nil?
        operations.each { |op| op.error :not_enough_gibson, 'There were not enough gibson aliquots to complete the operation.' }
        raise 'Aquarium cannot find any gibson aliquot batches in the system'
      end
      batch_id_array.push(gib_batch.id)
      total_aliquots += gib_batch.num_samples
    end

    # fetch gibson aliquots
    get_gibson_aliquots(batch_id_array)

    aliquots_needed
  end

  def create_volume_table(fragments:, fragment_volumes:)
    volume_entries = fragment_volumes.map { |v| { content: v, check: true } }
    entries = fragments.collect(&:id).zip(volume_entries)

    [['Fragment Stock IDs', 'Volume']].concat(entries)
  end

  def gibson_coefficients(row, col, concentration_vector)
    if row.zero?
      1
    elsif col.zero?
      concentration_vector[0]
    elsif row == col
      -concentration_vector[row]
    else
      0
    end
  end

  # this creates the "total_volume" row vector
  def gibson_vector(row)
    if row.zero?
      5.0
    else
      0
    end
  end

  def concentration_by_length(fragments)
    fragments.collect do |fragment|
      fragment.get(:concentration).to_f / fragment.sample.properties['Length']
    end
  end

  def build_coefficient_matrix(concentration_vector)
    Matrix.build(n, n) do |r, c|
      gibson_coefficients(r, c, concentration_vector)
    end
  end

  # For calculating equimolar concentrations, Yaoyu has written up a great explanation:
  # math behind the equimolar volume calculation
  # Assume that there are n fragment stocks, each with concentrations c1,..., cn, and lengths l1,...,ln.
  # The volumes of each fragment stocks to add in the Gibson reaction is denoted as v1,...,vn.
  # Assuming that the molecular weight (g/mol) of the fragment is proportional to the length of the fragment, to ensure equimolar of these n fragment stocks, the following must satisfy:
  #
  #   v1 + ... + vn = 5 (the total gibson reaction volume)
  #   v1 * c1 / l1 = ... = vn * cn / ln (they're equimolar)
  #
  # where the unit of v is uL, unit of c is g/uL, unit of l1 (molecular weight) is g/mol
  # Thus v * c / l represent the moles of the fragment stock, and ensuring v1 * c1 / l1 = ... = vn * cn / ln lead to equimolar fragment stocks.
  # These constraints can be reformated as:
  #
  #   v1 + ... + vn = 5
  #   v1 * c1 / l1 - v2 * c2 / l2 = 0
  #   v1 * c1 / l1 - v3 * c3 / l3 = 0
  #          ...
  #   v1 * c1 / l1 - vn * cn / ln = 0
  #
  # The following matrix equations hold:
  #
  #   coefficient_matrix * fragment_volumes = total_vector,
  #
  # where
  #   coefficient_matrix = [
  #     [1, 1, ..., 1]
  #     [c1 / l1, -c2 / l2, ..., 0]
  #     [c1 / l1, 0, - c3 / l3 ..., 0]
  #       ...
  #     [c1 / l1, 0, ..., - vn * cn / ln]
  #   ] is an n x n matrix,
  #   fragment_volumes = [[v1], [v2], ..., [vn]] (n x 1 matrix)
  #   total_vector = [[5], [0], ..., [0]] (n x 1 matrix)
  #
  # We can isolate the fragment volumes by matrix multiplication
  #
  #   coefficient_matrix.inv * coefficient_matrix * fragment_volumes = coefficient_matrix.inv * total_vector
  #
  # that yields
  #
  #   fragment_volumes = coefficient_matrix.inv * total_vector
  def calculate_gibson_volumes(fragments)
    concentration_vector = concentration_by_length(fragments)
    n = concentration_vector.length
    total_vector = Matrix.build(n, 1) { |r, _c| gibson_vector(r) }
    coefficient_matrix = build_coefficient_matrix(concentration_vector)
    fragment_volumes = coefficient_matrix.inv * total_vector
    volume_vector = fragment_volumes.each.to_a.collect! { |x| x.round(2) }
    f_vol = volume_vector.each.to_a.collect! { |x| x < 0.20 ? 0.20 : x }

    # this is to ensure that the rxn isn't > 5uL
    max = f_vol.max
    total = f_vol.reduce(:+)
    f_vol[f_vol.index(max)] = (max - (total - 5)).round(2) if total > 5

    # collect all volumes
    tot_f_vol = Hash.new(0)
    fragments.each_with_index do |fragment, i|
      tot_f_vol[fragment.id] = f_vol[i]
    end

    [tot_f_vol, f_vol]
  end

  def heat_block(operations)
    return unless operations.any?
    show do
      title 'Put Reactions on Heat Block'
      warning 'Vortex and spin all Gibson Reactions before putting them on the heat block!'
      note "Put all #{operations.length} on the 50 C heat block"
      note"<a href='https://www.google.com/search?q=1+hr+timer&oq=1+hr+timer&aqs=chrome..69i57j0l5.1684j0j7&sourceid=chrome&es_sm=122&ie=UTF-8#q=1+hour+timer' target='_blank'>
          Set a 1 hr timer on Google</a> to set a reminder to start the ecoli_transformation protocol and retrieve the Gibson Reactions."
    end
  end

  def get_replacement_array(fragment)
    Item.where(sample_id: fragment.sample_id)
        .where(object_type_id: fragment.object_type_id)
        .where('location != ?', 'deleted')
        .to_a
  end

  def find_replacements(replacement, to_discard, fragment_id, v)
    fragment = Item.find(fragment_id)
    replacement[fragment.id] = fragment
    is_bad_replacement = true

    # Keep finding replacements if previous replacement doesn't have enough volume
    while is_bad_replacement
      to_discard.push replacement[fragment.id]
      replacement[fragment.id].move_to('deleted')
      replacement[fragment.id].save
      replacement[fragment.id] = get_replacement_array(fragment).first
      # Only do this if there exists a replacement
      # has the tech confirm if the new replacement has enough volume
      if replacement[fragment.id]
        loop_check = show do
          title 'Find replacements'
          note "Retrieve #{replacement[fragment.id].id} from #{replacement[fragment.id].location}"
          select %w[Yes No], var: "v#{fragment_id}", label: "Does #{replacement[fragment.id].id} have at least #{v} uL?", default: 0
        end
        is_bad_replacement = loop_check["v#{fragment_id}".to_sym] != 'Yes'
      else # exit the loop if there are no replacements available
        show do
          title 'We couldnt find replacements.'
        end
        is_bad_replacement = false
      end
    end
  end

  def get_gibson_aliquots(batch_id_array)
    show do
      title 'Grab Gibson aliquots'
      note 'Grab an ice block and aluminum tray from the fridge'
      note "Grab #{operations.length} Gibson aliquots from batch#{'es' if batch_id_array.length > 1} #{batch_id_array}, located in the M20"
    end
  end

  def load_gibson_reaction(operation, vol_table)
    show do
      title "Load Gibson Reaction #{operation.output('Assembled Plasmid').item.id}"
      note "Label an unused aliquot with #{operation.output('Assembled Plasmid').item.id}"
      note 'Make sure the Gibson aliquot is thawed before pipetting'
      warning 'Please use the P2 for any volumes below 0.5 uL'
      table vol_table
    end
  end

  def return_aluminumTubeRack_and_iceBlock
    show do
      title 'Return ice block and aluminum tube rack'
      check 'Return the ice block and aluminum tube rack.'
      check 'discard the used up gibson aliquot batch.'
    end
  end

  def return_gibson_aliquots(aliquots_needed, batch_id_array)
    data = show do
      title 'Return unused gibson aliquots'
      note "#{aliquots_needed} aliquots were needed for this protocol, but you might have not used all of them."
      note "Return any unused aliquots to batch#{'es' if batch_id_array.length > 1} #{batch_id_array.reverse} in the M20"
      get 'number', var: 'n', label: 'How many gibson aliquots will be returned?', default: '0'
      note 'If you used more aliquots than predicted, indicate with a negative value.'
    end
    data # return
  end

  def associate_replacements(find_replacement, replacement, op)
    replacement.each do |id, item|
      if item

        op.input_array('Fragment').find { |fv| fv.item.id == id }.set item: item
        find_replacement.push(item)
      else
        op.error :volume, 'Insufficient fragment stock volume for Gibson reaction.'
        break
    end
    end
  end

  def update_gibson_batches(gibsons_used, batch_id_array)
    i = 0
    gib_batch = Collection.find batch_id_array[i]
    while gibsons_used > 0
      if gib_batch.empty?
        gib_batch.mark_as_deleted
        i += 1
        gib_batch = Collection.find batch_id_array[i]
      end

      gibsons_used -= 1
      gib_batch.remove_one
    end
    gib_batch
  end
end

```
