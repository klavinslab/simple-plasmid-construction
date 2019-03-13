# Make PCR Fragment

Makes PCR fragment from primers.

In this protocol, the technician combines primers and templates with a master mix
in a stripwell. They then run the PCR in a thermocycler.

Ran after **Extract Fragment** and before **Assemble Plasmid**.

### Inputs


- **Forward Primer** [FP]  
  - <a href='#' onclick='easy_select("Sample Types", "Primer")'>Primer</a> / <a href='#' onclick='easy_select("Containers", "Primer Aliquot")'>Primer Aliquot</a>

- **Reverse Primer** [RP]  
  - <a href='#' onclick='easy_select("Sample Types", "Primer")'>Primer</a> / <a href='#' onclick='easy_select("Containers", "Primer Aliquot")'>Primer Aliquot</a>

- **Template** [T]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "1 ng/ÂµL Plasmid Stock")'>1 ng/ÂµL Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "1 ng/ÂµL Fragment Stock")'>1 ng/ÂµL Fragment Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Unverified Plasmid Stock")'>Unverified Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Gibson Reaction Result")'>Gibson Reaction Result</a>
  - <a href='#' onclick='easy_select("Sample Types", "DNA Library")'>DNA Library</a> / <a href='#' onclick='easy_select("Containers", "50X PCR Template")'>50X PCR Template</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Unverified PCR Fragment")'>Unverified PCR Fragment</a>



### Outputs


- **Fragment** [F]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Stripwell")'>Stripwell</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def validate_property sample, field_name
  validation_block = Proc.new
  property = sample.properties[field_name]
  if property.nil?
    raise "Could not find property #{field_name}"
  end
  validation_block.call(sample, property)
end

# Appends associates msgs to plan and operation
def precondition_warnings op, msgs, key=:precondition_warnings, sep=";"
  plan = op.plan
  if plan
    plan_msg = op.plan.get key
    plan_msgs = plan_msg.split(sep).map { |x| x.strip } if plan_msg
  end
  plan_msgs ||= []
  op_msgs = []

  msgs.each { |valid, m|
    if valid
      plan_msgs.delete(m)
    else
      plan_msgs << m
      op_msgs << m
    end
  }
  op_msgs.uniq!
  plan_msgs.uniq!

  op.associate key, op_msgs.join(sep + " ")
  op.plan.associate key, plan_msgs.join(sep + " ") if op.plan
end

def precondition(op)
  ready = true
  msgs = []
  
  #output fragment must have length!
  if op.output("Fragment").sample.properties["Length"].nil? || op.output("Fragment").sample.properties["Length"] <= 0
      op.associate("Output Fragment must have a defined length!", "")
      return false
  end

  # Validate sample, valid_block, valid_message
  ["Forward Primer", "Reverse Primer"].each do |n|
    sample = op.input(n).sample

    msgs << validate_property(sample, "T Anneal") { |s, property|
      validator = Proc.new { |p| p.to_f.between?(0.01, 100) }
      msg = "T Anneal #{property} for Primer \"#{s.name}\" is invalid"
      [validator.call(property), msg]
    }
  end
  msgs.select! { |valid, m| !valid }
  msgs.compact!
  precondition_warnings op, msgs
  ready = false if msgs.any?
  ready
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

needs 'Cloning Libs/Cloning'
needs 'PCR Libs/GradientPcrBatching'
needs 'Standard Libs/Debug'
needs 'Standard Libs/Feedback'

class Protocol
  # I/O
  FWD = 'Forward Primer'
  REV = 'Reverse Primer'
  TEMPLATE = 'Template'
  FRAGMENT = 'Fragment'

  # other
  SEC_PER_KB = 30 # sec, extension timer per KB for KAPA

  # get the gradient PCR magic
  include Cloning
  include GradientPcrBatching
  include Debug
  include Feedback

  def main
    # grab all necessary items
    dilute_stocks_and_retrieve TEMPLATE
    kapa_stock_item = find(:sample, name: 'Kapa HF Master Mix')[0].in('Enzyme Stock')[0]
    take [kapa_stock_item], interactive: true,  method: 'boxes'

    # check the volumes of input primers for all operations, and ensure they are sufficient
    operations.each { |op| op.temporary[:primer_vol] = 2.5 }
    check_volumes [FWD, REV], :primer_vol, :make_aliquots_from_stock, check_contam: true

    # build a pcrs hash that groups pcr by T Anneal
    pcrs = build_pcrs_hash

    # show the result of the binning algorithm
    if debug
      pcrs.each_with_index do |pcr, idx|
        show { title "pcr #{idx}" }
        log_bin_info pcr
      end
    end

    # generate a table for stripwells
    stripwell_tab = build_stripwell_table pcrs

    # prepare and label stripwells for PCR
    prepare_stripwells stripwell_tab

    # add templates to stripwells for pcr
    load_templates pcrs

    # add primers to stripwells
    load_primers pcrs

    # add kapa master mix to stripwells
    add_mix stripwell_tab, kapa_stock_item

    # run the thermocycler
    start_pcr pcrs

    # store
    operations.running.store io: 'input', interactive: true, method: 'boxes'
    release [kapa_stock_item], interactive: true

    get_protocol_feedback

    { batches: pcrs }
  end

  # dilute to 1ng/uL stocks if necessary
  def dilute_stocks_and_retrieve(input)
    # only use inputs that haven't been diluted and that don't have diluted stocks already
    ops_w_undiluted_template = operations.reject { true }
    operations.each do |op|
      next if op.input(input).object_type.name.include?('1 ng/L') || op.input(input).object_type.name.include?('50X PCR Template') || op.input(input).object_type.name.include?('Unverified PCR Fragment')

      sample = op.input(input).sample
      ot_name = op.input(input).object_type.name.include?('Unverified') ? '1 ng/L Plasmid Stock' : '1 ng/L ' + sample.sample_type.name + ' Stock'
      diluted_stock = sample.in(ot_name).first

      if diluted_stock
        op.input(input).set item: diluted_stock
      else
        new_stock = produce new_sample sample.name, of: sample.sample_type.name, as: ot_name
        op.temporary[:diluted_stock] = new_stock

        ops_w_undiluted_template.push op
      end
    end

    # retrieve operation inputs (doesn't include the stocks replaced by diluted stocks above)
    ops_w_undiluted_template.retrieve

    # all stocks may be diluted already
    if ops_w_undiluted_template.empty?
      operations.retrieve
      return
    end

    # ensure concentrations
    check_concentration ops_w_undiluted_template, input

    # dilute stocks
    show do
      title 'Make 1 ng/L Template Stocks'

      check "Grab #{ops_w_undiluted_template.length} 1.5 mL tubes, label them with #{ops_w_undiluted_template.map { |op| op.temporary[:diluted_stock].id }.join(', ')}"
      check 'Add template stocks and water into newly labeled 1.5 mL tubes following the table below'

      table ops_w_undiluted_template
        .start_table
        .custom_column(heading: 'Newly-labeled tube') { |op| op.temporary[:diluted_stock].id }
        .input_item(input, heading: 'Template stock, 1 uL', checkable: true)
        .custom_column(heading: 'Water volume', checkable: true) { |op| op.input(input).item.get(:concentration).to_f - 1 }
        .end_table
      check 'Vortex and then spin down for a few seconds'
    end

    # Add association from which item the 1ng/ul dilution came from
    ops_w_undiluted_template.map { |op| op.temporary[:diluted_stock].associate(:diluted_from, op.input(input).item.id) }

    # return input stocks
    release ops_w_undiluted_template.map { |op| op.input(input).item }, interactive: true, method: 'boxes'

    # retrieve the rest of the inputs
    operations.reject { |op| ops_w_undiluted_template.include? op }.retrieve

    # set diluted stocks as inputs
    ops_w_undiluted_template.each { |op| op.input(input).set item: op.temporary[:diluted_stock] }
  end

  # TODO: dilute from stock if item is aliquot
  # Callback for check_volume.
  # takes in lists of all ops that have input aliquots with insufficient volume, sorted by item,
  # and takes in the inputs which were checked for those ops.
  # Deletes bad items and remakes each from primer stock
  def make_aliquots_from_stock(bad_ops_by_item, inputs)
    # bad_ops_by_item is accessible by bad_ops_by_item[item] = [op1, op2, op3...]
    # where each op has a bad volume reading for the given item

    # Construct list of all stocks needed for making aliquots. Error ops for which no primer stock is available
    # for every non-errored op that has low item volume,
    # replace the old aliquot item with a new one.
    aliquots_to_make = 0
    stocks = []
    ops_by_fresh_item = Hash.new(0)
    stock_table = [['Primer Stock ID', 'Primer Aliquot ID']]
    transfer_table = [['Old Aliquot ID', 'New Aliquot ID']]
    bad_ops_by_item.each do |item, ops|
      stock = item.sample.in('Primer Stock').first ######## items is a string?
      if stock.nil?
        ops.each { |op| op.error :no_primer, "You need to order a primer stock for primer sample #{item.sample.id}." }
        bad_ops_by_item.except! item
      else
        stocks.push stock
        aliquots_to_make += 1
        item.mark_as_deleted
        fresh_item = produce new_sample item.sample.name, of: item.sample.sample_type.name, as: item.object_type.name
        bad_ops_by_item.except! item
        ops_by_fresh_item[fresh_item] = ops
        ops.each do |op|
          input = inputs.find { |input| op.input(input).item == item }
          op.input(input).set item: fresh_item
        end
        stock_table.push [stock.id, { content: fresh_item.id, check: true }]
        if item.get(:contaminated) != 'Yes'
          transfer_table.push [item.id, { content: fresh_item.id, check: true }]
        end
      end
    end

    bad_ops_by_item.merge! ops_by_fresh_item
    take stocks, interactive: true

    # label new aliquot tubes and dilute
    show do
      title 'Grab 1.5 mL tubes'

      note "Grab #{aliquots_to_make} 1.5 mL tubes"
      note "Label each tube with the following ids: #{bad_ops_by_item.keys.map(&:id).sort.to_sentence}"
      note 'Using the 100 uL pipette, pipette 90uL of water into each tube'
    end

    # make new aliquots
    show do
      title 'Transfer primer stock into primer aliquot'

      note 'Pipette 10 uL of the primer stock into the primer aliquot according to the following table:'
      table stock_table
    end

    if transfer_table.length > 1
      show do
        title 'Transfer Residual Primer'

        note 'Transfer primer residue from the low volume aliquots into the fresh aliquots according to the following table:'
        table transfer_table
      end
    end

    release stocks, interactive: true
  end

  # build a pcrs hash that groups pcr by T Anneal
  def build_pcrs_hash
    pcr_operations = operations.map do |op|
      PcrOperation.new(
        extension_time: op.output(FRAGMENT).sample.properties['Length'] * SEC_PER_KB / 1000,
        anneal_temp: min(op.input(FWD).sample.properties['T Anneal'], op.input(REV).sample.properties['T Anneal']),
        unique_id: op.id
      )
    end

    result_hash = batch(pcr_operations)
    pcr_reactions = []
    result_hash.each do |thermocycler_group, row_groups|
      reaction = {}
      extension_time = thermocycler_group.max_extension + 60
      reaction[:mm], reaction[:ss] = extension_time.to_i.divmod(60)
      reaction[:mm] = "0#{reaction[:mm]}" if reaction[:mm].between?(0, 9)
      reaction[:ss] = "0#{reaction[:ss]}" if reaction[:ss].between?(0, 9)

      reaction[:ops_by_bin] = {}
      sorted_rows = row_groups.to_a.sort_by(&:min_anneal)
      sorted_rows.each do |row_group|
        reaction[:ops_by_bin][row_group.min_anneal.round(1)] = [].extend(OperationList)
        row_group.members.sort_by(&:anneal_temp).each do |pcr_op|
          reaction[:ops_by_bin][row_group.min_anneal.round(1)] << Operation.find(pcr_op.unique_id)
        end
      end

      # trim bin if we cant fit all rows into one thermocycler
      while reaction[:ops_by_bin].keys.size > 8
        extra_ops = reaction[:ops_by_bin][reaction[:ops_by_bin].keys.last]
        extra_ops.each do |op|
          op.error :batching_issue, "We weren't able to batch this operation into a running thermocycler for this Job, try again."
        end
        reaction[:ops_by_bin].except(reaction[:ops_by_bin].keys.last)
      end

      reaction[:bins] = reaction[:ops_by_bin].keys
      reaction[:stripwells] = []
      reaction[:ops_by_bin].each do |_bin, ops|
        ops.make
        reaction[:stripwells] += ops.output_collections[FRAGMENT]
      end
      pcr_reactions << reaction
    end
    pcr_reactions
  end

  # generate a table for stripwells
  def build_stripwell_table(pcrs)
    stripwells = pcrs.collect { |pcr| pcr[:stripwells] }.flatten
    stripwell_tab = [['Stripwell', 'Wells to pipette']] + stripwells.map { |sw| ["#{sw.id} (#{sw.num_samples <= 6 ? 6 : 12} wells)", { content: sw.non_empty_string, check: true }] }
  end

  # prepare and label stripwells for PCR
  def prepare_stripwells(stripwell_tab)
    show do
      title 'Label and prepare stripwells'

      note 'Label stripwells, and pipette 19 uL of molecular grade water into each based on the following table:'
      table stripwell_tab
      stripwell_tab
    end
end

  # add templates to stripwells for pcr
  def load_templates(pcrs)
    pcrs.each_with_index do |pcr, idx|
      show do
        title "Load templates for PCR ##{idx + 1}"

        pcr[:ops_by_bin].each do |_bin, ops|
          table ops
            .start_table
            .output_collection(FRAGMENT, heading: 'Stripwell')
            .custom_column(heading: 'Well') { |op| op.output(FRAGMENT).column + 1 }
            .input_item(TEMPLATE, heading: 'Template, 1 uL', checkable: true)
            .end_table
        end
        warning 'Use a fresh pipette tip for each transfer.'.upcase
      end
    end
  end

  # add primers to stripwells
  def load_primers(pcrs)
    pcrs.each_with_index do |pcr, idx|
      show do
        title "Load primers for PCR ##{idx + 1}"

        pcr[:ops_by_bin].each do |_bin, ops|
          table ops.start_table
                   .output_collection(FRAGMENT, heading: 'Stripwell')
                   .custom_column(heading: 'Well') { |op| op.output(FRAGMENT).column + 1 }
            .input_item(FWD, heading: 'Forward Primer, 2.5 uL', checkable: true)
                   .input_item(REV, heading: 'Reverse Primer, 2.5 uL', checkable: true)
                   .end_table
        end
        warning 'Use a fresh pipette tip for each transfer.'.upcase
      end
    end
  end

  # add kapa master mix to stripwells
  def add_mix(stripwell_tab, kapa_stock_item)
    show do
      title 'Add Master Mix'

      note "Pipette 25 uL of master mix (#{kapa_stock_item}) into stripwells based on the following table:"
      table stripwell_tab
      warning 'USE A NEW PIPETTE TIP FOR EACH WELL AND PIPETTE UP AND DOWN TO MIX.'
      check 'Cap each stripwell. Press each one very hard to make sure it is sealed.'
    end
  end

  # run the thermocycler and update the positions of the stripwells
  def start_pcr(pcrs)
    pcrs.each_with_index do |pcr, idx|
      is_gradient = pcr[:bins].length > 1
      # log_bin_info pcr # use for debugging bad binning behavior
      resp = show do
        if !is_gradient
          title "Start PCR ##{idx + 1} at #{pcr[:bins].first} C"

          check "Place the stripwell(s) #{pcr[:stripwells].collect(&:to_s).join(', ')} into an available thermal cycler and close the lid."
          get 'text', var: 'name', label: 'Enter the name of the thermocycler used', default: 'TC1'
          check "Click 'Home' then click 'Saved Protocol'. Choose 'YY' and then 'CLONEPCR'."
          check "Set the anneal temperature to <b>#{pcr[:bins].first} C</b>. This is the 3rd temperature."
        else
          title "Start PCR ##{idx + 1} (gradient) over range #{pcr[:bins].first}-#{pcr[:bins].last} C"
          check "Click 'Home' then click 'Saved Protocol'. Choose 'YY' and then 'CLONEPCR'."
          check 'Click on annealing temperature -> options, and check the gradient checkbox.'
          check "Set the annealing temperature range to be #{pcr[:bins].first}-#{pcr[:bins].last} C."
          note "Cancel this PCR batch if something doesn't look right, for example if the thermocycler does not allow this temperature range."
          select %w[yes no], var: 'batching_bad', label: 'Cancel this batch?', default: 1
          note 'The following stripwells are ordered front to back.'

          pcr[:stripwells].map.with_index do |sw, idx|
            temp = pcr[:ops_by_bin].keys[idx].to_f
            check "Place the stripwell #{sw} into a row of the thermocycler with the temperature as close as possible to <b>#{temp} C</b>"
          end
          get 'text', var: 'name', label: 'Enter the name of the thermocycler used', default: 'TC1'
        end
        check "Set the 4th time (extension time) to be #{pcr[:mm]}:#{pcr[:ss]}."
        check "Press 'Run' and select 50 uL."
      end

      impossible_pcr_handler(pcr) if resp.get_response(:batching_bad) == 'yes'

      # set the location of the stripwell
      pcr[:stripwells].flatten.each do |sw|
        sw.move resp[:name]
      end
    end
  end

  def impossible_pcr_handler(pcr)
    pcr[:ops_by_bin].each do |_bin, ops|
      ops.each do |op|
        op.error :batching_issue, "We weren't able to batch this operation into a running thermocycler for this Job, try again."
      end
    end
    pcr[:stripwells].each(&:mark_as_deleted)

    show do
      title 'Reaction Canceled'
      note 'All operations in this pcr reaction are canceled, try them again in a seperate job.'
      note 'The other Reactions will go forward as planned.'
    end
  end

  def log_bin_info(pcr)
    show do
      title 'bin info'
      note 'ops_by_bin'
      pcr[:ops_by_bin].each do |bin, ops|
        opids = ops.map(&:id)
        check "#{bin}  =>  #{opids}"
      end

      note 'bins'
      pcr[:bins].each do |bin|
        check bin.to_s
      end
    end
  end
end

```
