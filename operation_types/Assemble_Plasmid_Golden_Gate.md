# Assemble Plasmid Golden Gate

Assembles fragments with a Golden Gate master mix.

It combines fragments with a Golden Gate master mix according to calculated concentrations and then tells
the technician to place the mixture into a thermocycler to run.

Ran after *Make PCR Fragment* and before *Transform Cells*.
### Inputs


- **Backbone** [B]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Unverified Plasmid Stock")'>Unverified Plasmid Stock</a>

- **Inserts** [I] (Array) 
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Unverified Plasmid Stock")'>Unverified Plasmid Stock</a>



### Outputs


- **Plasmid** [AP]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Golden Gate Stripwell")'>Golden Gate Stripwell</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
    true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Protocol: Golden Gate Assembly
# Author: Justin Vrana
# Description: Golden Gate with BsaI using NEB Golden Gate Mix
# Revision: 2017-07-19, refactored to fix errors; Justin Vrana
# To Do:
#   1. Add creation of 40 fmol/ul stocks
#   2. Add parameter indicating whether finding replacements is OK
#   3. Error out protocols if there isn't enough volume and there isn't a replacement
needs "Standard Libs/Feedback"
class Protocol
    include Feedback
    # IO
        INSERTS = "Inserts"
        BACKBONE = "Backbone"
        PLASMID = "Plasmid"
  
    # Config
        INSERT_TO_BACKBONE = 2.0
        TVOL = 10.0
        BACKBONE_FMOL_PER_UL = 2.0
        BACKBONE_FMOL = BACKBONE_FMOL_PER_UL * TVOL
        
        # 1-4 inserts >> 37C, 1hr > 55C, 5min
        # 5-10 inserts >> (37C 1 min, 16C 1 min) X 30 > 55C, 5 min
        # 11-20 inserts >> (37C 5 min, 16C 5 min) X 30 > 55C, 5 min
        THERMOCYCLER_CONDITIONS = {
                0=>{
                    :condition=> Proc.new { |op| op.input_array(INSERTS).size.between?(1,4) },
                    :steps=>
                    [
                        {:temp=>37, :min=>60}, 
                        {:temp=>55, :min=>5},
                    ]
                },
                1=>{
                    :condition => Proc.new { |op| op.input_array(INSERTS).size.between?(5,10) },
                    :steps =>
                    [
                        {:temp=>37, :min=>1}, 
                        {:temp=>16, :min=>1}, 
                        {:goto=>1, :times=>30}, 
                        {:temp=>55, :min=>5},
                    ]
                },
                2=>{
                    :condition => Proc.new { |op| op.input_array(INSERTS).size.between?(11,20) },
                    :steps =>
                    [
                        {:temp=>37, :min=>5}, 
                        {:temp=>16, :min=>5}, 
                        {:goto=>1, :times=>30}, 
                        {:temp=>55, :min=>5},
                    ]
                }
            }
        AVAILABLE_THERMOCYCLERS = ["T1", "T2", "T3"]
        REPLACEMENTS_OK = false # whether its ok to find replacements for dnas whose volume has run out
        
    # testing configuration
        RUN_WITH_PRECHECK_ERRORS = false                 # errors out myops in debug mode in precheck if true
        RANDOMIZE_THERMOCYCLER_GROUPS = true    # randomizes thermocycler groups in debug mode if true
        RUN_WITH_POSTCHECK_ERRORS = false    # errors out some operation in post check to test
        TEST_NOT_ENOUGH_THERMOCYCLERS = false
        TEST_ITEM_REPLACEMENT = false # replaces first item in operation
        SIMULATE_SAME_BACKBONE = true # simulates the situation in which the same backbone is used for all myops
        
    # Protocol Methods
        def ng_to_fmol(ng, length)
            ng * (1.0/660.0) * 10**6 * (1.0/length)
            # fmol = ng * 1pmol/660pg * 1000pg/1ng * 1/N * 1000fmol/1pmol
        end

    def main
        # DEBUG: Show Protocol Configuration
            if debug
                show do
                    title "DEBUG: Protocol Configuration"

                    note "RUN_WITH_PRECHECK_ERRORS = #{RUN_WITH_PRECHECK_ERRORS}"
                    note "RANDOMIZE_THERMOCYCLER_GROUPS = #{RANDOMIZE_THERMOCYCLER_GROUPS}"
                    note "TEST_NOT_ENOUGH_THERMOCYCLERS = #{TEST_NOT_ENOUGH_THERMOCYCLERS}"
                    note "TEST_ITEM_REPLACEMENT = #{TEST_ITEM_REPLACEMENT}"
                    note "SIMULATE_SAME_BACKBONE = #{SIMULATE_SAME_BACKBONE}"
                end
            end
            
        
        
        # Estimate total thermocycler time
            estimated_time = Hash.new
            
            
            THERMOCYCLER_CONDITIONS.keys.each do |tgroup|
                tinfo = THERMOCYCLER_CONDITIONS[tgroup]
                steps = tinfo[:steps]
                steps_dup = steps.map { |step| step.dup } # duplicate steps
                curr_step = 1
                cumulative_time = 0    # cumulative thermocycler time
                counter = 0            # failsafe to prevent infinite loops that kills Krill
                while curr_step.between?(0,steps.size) and counter < 200
                    counter += 1
                    step_index = curr_step-1
                    step = steps[step_index]
                    if step[:min]
                        cumulative_time += step[:min]
                    elsif step[:goto] and step[:times]
                        if step[:times] > 0
                            curr_step = step[:goto] - 1
                            steps_dup[step_index][:times] -= 1
                        end
                    end
                    curr_step += 1
                end
                estimated_time[tgroup] = cumulative_time
            end
        
            operations.retrieve interactive: true
         
        # Define virtual operations         
            dna_inputs = operations.running.map { |op| [op.input(BACKBONE), op.input_array(INSERTS)] }.flatten
            dna = dna_inputs.map { |di| di.item }.uniq
            
            # fix data associations
            dna.each do |d|
                d.associate :volume, d.get(:volume).to_f
                d.associate :concentration, d.get(:concentration).to_f
            end
            
            myops = operations.running
            
        
        # Calculations
            myops.each do |op|
                # Lengths
                    bb = op.input(BACKBONE).sample
                    inserts = op.input_array(INSERTS).map { |insert| insert.sample }
                    op.temporary[:backbone_length] = bb.properties['Length'].to_f || 0
                    op.temporary[:insert_lengths] = inserts.map do |insert| 
                        insert.properties['Length'].to_f || 0
                    end
                
                # Markers
                    op.temporary[:backbone_marker] = bb.properties['Bacterial Marker']
                    op.temporary[:insert_markers] = inserts.map do |insert|
                        insert.properties['Bacterial Marker']
                    end
                    op.temporary[:plasmid_marker] = op.output(PLASMID).sample.properties['Bacterial Marker']
                
                # Concentrations
                    # Attempt to grab legacy data and add it as a data association
                    # op.temporary[:backbone_concentration] = op.input(BACKBONE).item.get(:concentration).to_f
                    # op.temporary[:insert_concentrations] = op.input_array(INSERTS).map { |i| i.item.get(:concentration).to_f }
                    
                # Thermocycler Groups
                    THERMOCYCLER_CONDITIONS.each do |tgroup, info|
                        myops.running.select(&info[:condition]).each do |op|
                            op.temporary[:thermocycler_group] = tgroup
                        end
                    end
            end
        
        # Validate Lengths
            myops.each do |op|
                dna_inputs = [op.input(BACKBONE)] + op.input_array(INSERTS) # an array of backbone + inserts

                lengths = [op.temporary[:backbone_length]] + op.temporary[:insert_lengths]
                lengths.map! { |x| x.to_f }
                lengths.zip(dna_inputs).each.with_index do |ld, index|
                    length, d = ld
                    if length <= 0
                        err_key = "no_length_for_#{d.sample.name}".to_sym
                        err_msg = "The input dna #{d.sample.name} has an invalid DNA length. Please input \
                            a valid length in the sample definition."
                        if debug
                            if RUN_WITH_PRECHECK_ERRORS
                                op.error err_key, err_msg
                            elsif # Assign random length in debug mode
                                if index == 0
                                    op.temporary[:backbone_length] = rand(1000...10000)
                                else
                                    op.temporary[:insert_lengths][index-1] = rand(1000...10000)
                                end
                            end
                        else
                            op.error err_key, err_msg
                        end
                    end
                end
            end
            
            dna_inputs = operations.running.map { |op| [op.input(BACKBONE), op.input_array(INSERTS)] }.flatten
            dna = dna_inputs.map { |di| di.item }.uniq
            vops = dna.map { |i|
                insert_operation operations.length, VirtualOperation.new
                vop = operations.last
                vop.temporary[:item] = i
                vop
              }
              
            myops = operations.select { |op| !op.virtual? }
            
            if myops.empty?
                show do
                    title "There are no operations"
                    
                    check "All the operations have errored out."
                end
            end
            
        # DEBUG: 
            if debug and SIMULATE_SAME_BACKBONE
                backbone = nil
                myops.running.each do |op|
                    if not backbone
                        backbone = op.input(BACKBONE).item
                    else
                        fv = op.input(BACKBONE)
                        fv.child_item_id = backbone.id
                        fv.save
                    end
                end
            end

        # You may know beforehand that you don't have enough volume but need a replacement
        # add additional items here
            
        # Measure Concentrations
            def concentration_invalid item
                invalid = false
                if item.get(:concentration).nil? or item.get(:concentration).to_f <= 0.0
                    invalid = true
                end
                invalid
            end
            
            dna_to_be_measured = dna.select { |d| concentration_invalid(d) }
            
            # Loop if any concentrations are invalid
                counter = 0 # failsafe to prevent infinite loops that wreck Krill
                while dna_to_be_measured.any? { |d| concentration_invalid(d) } and counter < 5
                    
                    counter += 1
                    temp_op = myops.first
                    message = nil
                    if counter > 1
                        message = "One or more concentrations you've entered are invalid! \
                            Please correct the concentration of highlighted item."
                    end
                    # Ask technician to nanodrop each plasmid
                        show do
                            title "Go to the nanodrop and measure the concentrations."
                            warning message if message
                            check "For each concentration, write the concentration on the side of the tube"
                            note "Enter the concentrations in the table below."
                            
                            css_incorrect = {style: {color: "white", "background-color"=>"red"}}
                            # Make IO Table
                                item_id_rows, conc_rows = [], []
                                dna_to_be_measured.map do |dna|
                                    item_id_row = { content: dna.id, check: true }
                                    item_id_row.merge!(css_incorrect) if concentration_invalid(dna) and message
                                    item_id_rows.push(item_id_row)
                                    
                                    conc_row = {
                                        type: 'number', 
                                        key: "#{dna.id}_concentration", 
                                        operation_id: temp_op.id, 
                                        default: concentration_invalid(dna) ? -1 : dna.get(:concentration)
                                    }
                                    conc_row.merge!(css_incorrect) if concentration_invalid(dna)
                                    conc_rows.push(conc_row)
                                end
                                
                                io_table = Table.new
                                io_table.add_column("Item id", item_id_rows)
                                io_table.add_column("Concentration (ng/ul)", conc_rows)
                                table io_table
                        end
                        
                    # Concentration data associations
                        dna_to_be_measured.each do |dna|
                            key = "#{dna.id}_concentration".to_sym
                            dna.associate :concentration, temp_op.temporary[key].to_f
                            dna.save
                            temp_op.temporary.delete(key)
                        end
                        
                    # Debug test
                    if debug
                        dna_to_be_measured.each do |dna|
                            dna.associate :concentration, rand(100...1000)
                        end
                        if counter == 1
                            dna_to_be_measured.first.associate :concentration, -1
                        end
                    end
                        
                    # Update remove valid dnas from measurement lists
                    #     dna_to_be_measured.reject! { |d| !concentration_invalid(d.item) }
                end
            
         # Find item replacements
            if debug and TEST_ITEM_REPLACEMENT
                # replace first operation
                fmol_stock = ObjectType.find_by_name("40 fmole/uL Plasmid Stock")
                fv = myops.running.first.input(BACKBONE)
                child_sample = fv.child_sample
                new_item = Item.make( {quantity: 1, inuse: 0}, sample: child_sample, object_type: fmol_stock )
                fv.child_item_id = new_item.id
                fv.save
                
                show do
                    title "DEBUG: Item Replacement"
                    note "#{new_item.id}"
                    table myops.running.start_table
                        .custom_column(heading: "Field Value Type") { |op| op.input(BACKBONE).object_type.name }
                        .custom_column(heading: "Item Type") { |op| op.input(BACKBONE).item.object_type.name }
                        .input_item(BACKBONE)
                        .end_table
                end
            end
        
        # Volume Calculations
            myops.running.each do |op|
                # Volumes
                
                    recipe = Hash.new
                    # Backbone volume
                    
                        bb_fmol_per_uL = ng_to_fmol(op.input(BACKBONE).item.get(:concentration), op.temporary[:backbone_length])
                        recipe[op.input(BACKBONE).item] = BACKBONE_FMOL / bb_fmol_per_uL
                    
                    # Insert volumes
                        ics = op.input_array(INSERTS).map { |insert| insert.item.get(:concentration) }
                        ils = op.temporary[:insert_lengths]
                        op.input_array(INSERTS).zip(ils).map do |insert_input, l|
                            c = insert_input.item.get(:concentration)
                            fmol_per_ul = ng_to_fmol(c, l)
                            recipe[insert_input.item] = (INSERT_TO_BACKBONE * BACKBONE_FMOL).to_f / (fmol_per_ul).to_f
                        end
                    
                    # Buffer volume
                        recipe[:buffer] = TVOL * 0.1
                    
                    # Enzyme volume
                        recipe[:enzyme] = TVOL * 0.05
                        
                    # H20 volumes
                        total_vol = recipe.inject(0) { |sum, x| sum + x[1] }
                        adjustment = total_vol / TVOL
                        if adjustment > 1.0
                            recipe.each do |k, v|
                                recipe[k] = v / adjustment
                            end
                        end
                        total_vol = recipe.inject(0) { |sum, x| sum + x[1] }
                        recipe[:water] = TVOL - total_vol
                        
                    # Round
                        recipe.each do |k, v|
                            recipe[k] = recipe[k]
                        end
                    
                    # Recipe
                        op.temporary[:recipe] = recipe
                        
                    # Adjustments
            end
            
            
            
        # DEBUG: Volume Calculation Table
            if debug
                show do
                    title "DEBUG: Volume Calculations"
                    table myops.running.start_table
                        .custom_column(heading: "Backbone Vol") { |op| op.temporary[:recipe][op.input(BACKBONE).item] }
                        .custom_column(heading: "Insert Vols") { |op| op.input_array(INSERTS).map { |i| op.temporary[:recipe][i.item] } }
                        .custom_column(heading: "Backbone Length") { |op| op.temporary[:backbone_length] }
                        .custom_column(heading: "Insert Lengths") { |op| op.temporary[:insert_lengths] }
                        .custom_column(heading: "Backbone Conc") { |op| op.input(BACKBONE).item.get(:concentration) }
                        .custom_column(heading: "Insert Conc") { |op| op.input_array(INSERTS).map { |insert| insert.item.get(:concentration) } }
                        .end_table
                end
            end
            
        # Validate volumes
            # vol_hash = validate_volumes(myops.running, debug_mode=RUN_WITH_POSTCHECK_ERRORS, BACKBONE, INSERTS)
                vol_hash = Hash.new # h[d] = { :total_vol, :ops }
                input_names = [INSERTS, BACKBONE]
                myops.running.each do |op|
                    inputs = input_names.map { |name| op.input_array(name) }.flatten # array of all fields
                    items = inputs.map { |input| input.item }.uniq # list of unique items
                    req_vols = items.map { |item| op.temporary[:recipe][item] }
                    items.zip(req_vols).each do |i, v|
                        item_info = vol_hash[i] || { :total_vol=>0, :ops=>[] }
                        item_info[:total_vol] += v
                        item_info[:ops].push(op)
                        vol_hash[i] = item_info # {total_vol: total_volume_required, ops: ops_associated_with_this_item}
                    end
                end
            
            # Check volumes
            volume_table = Proc.new { |ops|
                ops.start_table
                    .custom_column(heading: "Item") { |op| op.temporary[:item].id }
                    .custom_column(heading: "Total vol req. for batch") { |op| vol_hash[op.temporary[:item]][:total_vol] }
                    .custom_column(heading: "Num Times Used") { |op| vol_hash[op.temporary[:item]][:ops].size }
                    .custom_input(:volume, heading: "Volume (ul)", type: "number") { |op|
                        default_volume = op.temporary[:item].get(:volume) || 10.0
                        if debug and default_volume == 0.0
                            default_volume = rand(10..100)
                        end
                        default_volume
                    }
                    .validate(:volume) { |op,v| v.between?(0,10000) }
                    .end_table.all
            }
            
            show_with_input_table(vops, volume_table) do
                title "Check volumes"
                
                check "For each item, estimate the volume in the tube"
            end
            
            # Associate volumes
            vops.each do |op| 
                op.temporary[:item].associate :volume, op.temporary[:volume]
            end
            
            vol_remaining_hash = vol_hash.map { |item, vol| [item, item.get(:volume)] }.to_h # simulated volume remaining for each item
            requires_replacement = [] # items that require replacement
            replacement_reasons = [] # reason for replacement
            
            myops.running.each do |op|
                op.temporary[:replace] = []
                input_names = [BACKBONE, INSERTS]
                input_fields = input_names.map { |n| op.input_array(n) }.flatten  # all inputs
                items = input_fields.map { |input| input.item }.uniq    # uniq items for the inputs
                recipe = op.temporary[:recipe]  # recipe detailing how much vol is needed for each item
                items.each do |item|
        
                    # Contamination check
                        if item[:contamination] == true
                            op.temporary[:replace].push(item)
                            "Item #{item.id} was contaminated. Please see associated notes."
                        end

                    # Volume check
                        req_vol = recipe[item]
                        vol_remaining = vol_remaining_hash[item]
                        vol_remaining_hash[item] -= req_vol
                        if vol_remaining_hash[item] < 0
                            op.temporary[:replace].push(item)
                            op.error :not_enough_volume, "Item #{item.id} did not have enough volume to complete operation #{op.id}."
                        end
                end
                op.temporary[:replace].uniq!
            end
            
            myops.running.each do |op|
                items_to_be_replaced = op.temporary[:replace]
            end
            
            requires_replacement = requires_replacement.uniq
            
            # ops_to_be_diluted = vol_hash.select { |item, info| info[:total_vol]
            
            
            # allowable_objects = 
            
            # ft = myops.first.input("Input").field_type
            # allowable_ft = ft.allowable_field_types
            # allowable_objects = allowable_ft.map { |f| ObjectType.find_by_id(f.object_type_id) }
            # x = FieldType.find_by_id(x)
            # note "#{allowable_objects.map { |x| x.name } }"
            
            
            # retrieve the replacement items
            # re-validate volumes for those items
            # if there's not enough, repeat
                # if there's no more items, error out the operation
            
            
            # if replacements are ok
                # treat all dnas as a pool
                # if contaminated
                    # find replacment item
                    # notify user of replacement
                # if not enough volume between entire pool
                    # error out some myops
                    
            # for volumes below pipetting threshold
                # create a 40 fmol/stock
                # set input item to 40 fmol/stock
                # notify user of replacement
        
        # Custom Make
            if debug and 
                # Tests to make sure thermocycler grouping is working properly
                myops.running.each do |op|
                    op.temporary[:thermocycler_group] = THERMOCYCLER_CONDITIONS.keys.sample
                end
            end
        
            thermocycler_groups = myops.running.group_by { |op| op.temporary[:thermocycler_group] }
            
            thermocycler_groups.each do |gn, op_group|
                fo = op_group.first.output(PLASMID)
                rows = fo.object_type.rows
                columns = fo.object_type.columns
                size = rows * columns
                new_collection = op_group.first.output(PLASMID).make_collection
                op_group.each.with_index do |op, i|
                    fv = op.output(PLASMID)
                    fv.make_part(new_collection,(i%size)/columns,(i%size)%columns)
                end
            end
            
            if debug
                show do
                    title "DEBUG: Output Collections"
                    table myops.running.start_table
                        .output_collection(PLASMID)
                        .output_column(PLASMID)
                        .end_table
                end
            end
        
        # Group myops by stripwells
            stripwells = myops.running.map { |op| op.output(PLASMID).collection }.uniq
            
            grouped_by_stripwells = stripwells.map do |stripwell|
                grouped_ops = myops.running.select do |op| 
                    op.output(PLASMID).collection == stripwell
                end
                [stripwell, grouped_ops]
            end.to_h
        
        
        # Prepare Golden Gate Master Mix
            # For NEB reaction, we just grab it from the stock (BsaI only)
            # For other enzymes, we have to make this fresh each time...
        
        # Gather and label stripwells
            show do
                title "Gather and label #{stripwells.size} stripwell(s)"
                
                note "Gather #{stripwells.size} stripwell(s) and label them according to the table:"
                
                t = Table.new
                t.add_column("Stripwell IDs", stripwells.map { |s| s.id })
                table t
            end
        
        # Pipette H20
            grouped_by_stripwells.each do |stripwell, ops|
                show do
                   title "Pipette sterile H20 into stripwell #{stripwell}" 
                   note "Display a nice table indicating which stripwells..."
                   table ops.start_table
                    .output_collection(PLASMID, heading: "Stripwell")
                    .output_column(PLASMID, heading: "Well", checkable: true)
                    .custom_column(heading: "H20 (uL)") { |op| op.temporary[:recipe][:water] }
                    .end_table
                end
            end
            
        # Pipette Buffer
            # for non-NEB, we don't need to add buffer since it will be in the assembly mix...
            grouped_by_stripwells.each do |stripwell, ops|
                buffer = "NEB Golden Gate Buffer"
                show do 
                    title "Pipette #{buffer} into each well"
                    
                    table ops.start_table
                        .output_collection(PLASMID, heading: "Stripwell")
                        .output_column(PLASMID, checkable: true, heading: "Well")
                        .custom_column(heading: "Vol (ul)") { |op| op.temporary[:recipe][:buffer] }
                        .end_table
                end
            end
        
        # Pipette DNA
            grouped_by_stripwells.each do |stripwell, ops|
                ops.running.each do |op|
                    show do
                        title "Add DNA to well #{op.output(PLASMID).column} of stripwell #{op.output(PLASMID).collection}"
                        note "Stripwell: #{op.output(PLASMID).collection}"
                        note "Well: #{op.output(PLASMID).column}"
                        
                        these_dna = op.input_array(BACKBONE) + op.input_array(INSERTS)
                        
                        t = Table.new
                        t.add_column( "Item id", these_dna.map { |d| { content: d.item.id, check: true } } )
                        t.add_column("Vol (ul)", these_dna.map { |d| op.temporary[:recipe][d.item] } )
                        table t
                    end
                    
                    # note "UPDATE VOLUMES HERE"
                    # note "CREATE A TRANSFER METHOD FOR TRANSFERS BETWEEN ITEMS"
                end
            end
            
        # Pipette Assembly Mix
            assembly_mix = "NEB Golden Gate Assembly Mix"
            show do 
                title "Pipette #{assembly_mix} into each well"
                    
                table myops.running.start_table
                    .output_collection(PLASMID, heading: "Stripwell")
                    .output_column(PLASMID, checkable: true, heading: "Well")
                    .custom_column(heading: "Vol (ul)") { |op| op.temporary[:recipe][:enzyme] }
                    .end_table
            end
            
        # Put in thermocyclers
            thermocycler_ids = thermocycler_groups.keys.sort
            available_thermocyclers = AVAILABLE_THERMOCYCLERS.dup
            if debug and TEST_NOT_ENOUGH_THERMOCYCLERS
                available_thermocyclers = []
            end
            thermocycler_ids.each do |group_id|
                op_group = thermocycler_groups[group_id] # myops grouped into this thermocycler
                stripwells = op_group.map { |op| op.output(PLASMID).collection }.uniq # stripwells for this thermocycler
                
                thermocycler = :unknown_location # thermocycler location
                if available_thermocyclers.any?
                    thermocycler = available_thermocyclers.slice!(0)
                end
                steps = THERMOCYCLER_CONDITIONS[group_id][:steps] # thermocycler steps
                
                new_thermocycler_loc = show do
                    if thermocycler == :unknown_location
                        title "Find a thermocycler to place stripwells in"
                        
                        warning "There are no available thermocyclers for these stripwells!"
                        check "Please find an available thermocycler to place this golden gate in."
                        check "Please write down new location in the text box below!"
                        
                        get "text", var: "location", label: "New stripwell location:", default: thermocycler
                    else
                        title "Place stripwells into thermocycler #{thermocycler}"
                    end
                    
                    separator
                    # Est Time
                        note "<b>Timing</b>"
                        note "Estimated duration: <b>#{estimated_time[group_id]} minutes</b>"
                        ready = Time.now + 60.0*estimated_time[group_id]
                        note "Thermocycler ready at: <b>#{ready.strftime("%a %m/%d/%y %I:%M%p")}</b>"
                    
                    separator
                    # Stripwell table
                        note "<b>Stripwells</b>"
                        st = Table.new
                        st.add_column("Stripwells", stripwells.map { |x| x.id })
                        table st
                    
                    step_strs = steps.map do |step|
                        str = step.to_s
                        if step[:temp] and step[:min]
                            str = "#{step[:temp]}C for #{step[:min]} minutes"
                        elsif step[:goto] and step[:times]
                            str = "GOTO Step #{step[:goto]} X#{step[:times]}"
                        end
                        str
                    end
                    
                    separator
                    # Thermocycler table
                        note "<b>Thermocycler Protocol</b>"
                        tt = Table.new
                        tt.add_column("Step", steps.map.with_index { |x, i| i+1 } )
                        tt.add_column("Protocol", step_strs)
                        table tt
                end
                
                # Update stripwell locations
                    thermocycler = new_thermocycler_loc[:location]
                    stripwells.each do |stripwell|
                        stripwell.move thermocycler
                    end
            end
        
        # Delete items whose volumes are now zero
            # code here
        
        # Return items
            myops.running.store(io: "input")
            myops.running.store(io: "output", interactive: false)
            
            get_protocol_feedback()
    
        return {}
    end
end
```
