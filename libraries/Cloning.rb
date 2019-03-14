module Cloning
  
  def check_concentration operations, input_name
    items = operations.collect { |op| op.input_array(input_name).items.select { |i| i.get(:concentration).nil? } }.flatten.uniq
    
    cc = show do 
      title "Please nanodrop the following #{items.first.object_type.name.pluralize}"
      note "Please nanodrop the following #{items.first.object_type.name.pluralize}:"
      items.each do |i|
        get "number", var: "c#{i.id}", label: "#{i} item", default: 42
      end
    end if items.any?
    
    items.each do |i|
      i.associate :concentration, cc["c#{i.id}".to_sym]
    end
  end
  
    
 # The check_volumes method will have the lab tech ensure that the given input item volumes are above a certain minimum amount, 
  # for each operation. The inputs to check are specified in an array parameter. 
  # The minimum volume is specified in mL on a per-operation basis using the the value stored in op.temporary[<vol_sym>],
  # where vol_sym is a symbol name of your choice. 
  # Contamination can be checked for too, with the additional option parameter check_contam: true
  # After determining which inputs for which ops are low volume, this method passes off a hash of 'items -> lists of ops' to your rebuilder function specified by name as string or symbol in the callback argument.
  # when the callback method returns, check_volumes loops back and checks the volumes again of the newly assigned unverified input items, and repeats this loop until all given inputs for all ops are verified for their volume.
  # for a detailed example of how this method can be used, look at the method call in make PCR fragment, and the callback function make_aliquots_from_stock
  def check_volumes inputs, vol_sym, callback, options = {}  
    
    ops_by_item = Hash.new(0)
    operations.running.each do |op|
      inputs.each do |input|
        if ops_by_item.keys.include? op.input(input).item
          ops_by_item[op.input(input).item].push op
        else
          ops_by_item[op.input(input).item] = [op] 
        end
      end
    end
      
    # while any operations for any of the specified inputs are unverified, check the volumes again and send any bad op/input combos to rebuilder function
    while ops_by_item.keys.any?
      verify_data = show do
        title "Verify enough volume of each #{inputs.to_sentence(last_word_connector: ", or")} exists#{options[:check_contam] ? ", or note if contamination is present" : ""}"
        
        ops_by_item.each do |item, ops| 
          volume = 0.0
          ops.each { |op| volume += op.temporary[vol_sym] }
          volume = (volume*100).round / 100.0
          choices = options[:check_contam] ? ["Yes", "No", "Contamination is present"] : ["Yes", "No"]
          select choices, var: "#{item.id}", label: "Is there at least #{volume} µL of #{item.id}?", default: 0
        end
      end
      ops_by_item.each do |item, ops|
        if verify_data["#{item.id}".to_sym] == "Yes"
          ops_by_item.except! item
        elsif verify_data["#{item.id}".to_sym] == "Contamination is present"
          item.associate(:contaminated, "Yes")
        end
      end
      method(callback.to_sym).call(ops_by_item, inputs) if ops_by_item.keys.any?
    end
  end
  
  # a common callback for check_volume.
  # takes in lists of all ops that have input aliquots with insufficient volume, sorted by item,
  # and takes in the inputs which were checked for those ops.
  # Deletes bad items and remakes each primer aliquots from primer stock
  def make_aliquots_from_stock bad_ops_by_item, inputs
    # bad_ops_by_item is accessible by bad_ops_by_item[item] = [op1, op2, op3...]
    # where each op has a bad volume reading for the given item
    
    # Construct list of all stocks needed for making aliquots. Error ops for which no primer stock is available
    # for every non-errored op that has low item volume,
    # replace the old aliquot item with a new one. 
    aliquots_to_make = 0
    stocks = []
    ops_by_fresh_item = Hash.new(0)
    found_items = []
    stock_table = [["Primer Stock ID", "Primer Aliquot ID"]]
    transfer_table = [["Old Aliquot ID", "New Aliquot ID"]]
    bad_ops_by_item.each do |item, ops|
        
      #first, check to see if there is a replacement aliquot availalbe in the inventory
      fresh_item = item.sample.in("Primer Aliquot").reject {|i| i == item }.first
      
      if fresh_item
        #if a replacement item was found in the inventory, snag it
        found_items.push fresh_item
      else
        # no replacement, found, lets try making one.
        stock = item.sample.in("Primer Stock").first
        if stock.nil?
          # no stock found, replacement could not be made or found: erroring operation
          ops.each { |op| op.error :no_primer_stock, "aliquot #{item.id} was bad and a replacement could not be made. You need to order a primer stock for primer sample #{item.sample.id}." }
          bad_ops_by_item.except! item
        else
          stocks.push stock
          aliquots_to_make += 1
          fresh_item = produce new_sample item.sample.name, of: item.sample.sample_type.name, as: item.object_type.name
          stock_table.push [stock.id, {content: fresh_item.id, check: true}]
        end
      end
      
      if fresh_item
        # for the items where a replacement is able to be found or made, update op item info
        item.mark_as_deleted
        bad_ops_by_item.except! item
        ops_by_fresh_item[fresh_item] = ops
        ops.each do |op| 
          input = inputs.find { |input| op.input(input).item == item }
          op.input(input).set item: fresh_item
        end
        if item.get(:contaminated) != "Yes"
          transfer_table.push [item.id, {content: fresh_item.id, check: true}]    
        end
      end
    end
    
    take found_items, interactive: true if found_items.any?
    #items are guilty untill proven innocent. all the fresh items will be put back into the list of items to check for volume
    bad_ops_by_item.merge! ops_by_fresh_item
    take stocks, interactive: true if stocks.any?
    
    # label new aliquot tubes and dilute
    show do 
      title "Grab 1.5 mL tubes"
      
      note "Grab #{aliquots_to_make} 1.5 mL tubes"
      note "Label each tube with the following ids: #{bad_ops_by_item.keys.reject { |item| found_items.include? item }.map { |item| item.id }.sort.to_sentence}"
      note "Using the 100 uL pipette, pipette 90uL of water into each tube"
    end if bad_ops_by_item.keys.reject { |item| found_items.include? item }.any?
  
    # make new aliquots
    show do 
      title "Transfer primer stock into primer aliquot"
      
      note "Pipette 10 uL of the primer stock into the primer aliquot according to the following table:"
      table stock_table
    end if stocks.any?
    
    
    if transfer_table.length > 1
      show do
        title "Transfer Residual Primer"
        
        note "Transfer primer residue from the low volume aliquots into the fresh aliquots according to the following table:"
        table transfer_table
      end
    end
    
    release stocks, interactive: true if stocks.any?
  end
  
  def incubate operations, shaker, input_name, output_name
    operations.each { |op|
        op.output(output_name).item.move "#{op.input(input_name).sample.properties["Transformation Temperature"].to_i} C #{shaker} incubator"
    }
  end
  
  
  
  # Associates specified associations + uploads from :from to :to. This is used primarily to pass sequencing results through items in a plasmid's lineage
  #   e.g., pass_data "sequence_verified", "sequencing results", from: overnight, to: glycerol_stock
  #   This will copy all sequencing results and the sequence_verified associations from the overnight to the glycerol stock
  def pass_data *names, **kwargs
    from = kwargs[:from]
    to = kwargs[:to]
    names.each do |name|
      keys = from.associations.keys.select { |k| k.include? name }
      keys.each do |k|
        to.associate k, from.get(k), from.upload(k)
      end
    end
  end
  
end

   