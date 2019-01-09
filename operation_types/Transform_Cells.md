# Transform Cells

This is run after **Assemble Plasmid** and is a precursor to **Plate Transformed Cells**. The technician retrieves the inputted plasmid and, using DH5a E. coli competent cells, performs electroporation. The electeroporated cells are then inoculated in LB for an hour.
### Inputs


- **Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Gibson Reaction Result")'>Gibson Reaction Result</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Ligation product")'>Ligation product</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "1 ng/µL Plasmid Stock")'>1 ng/µL Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "DNA Mix")'>DNA Mix</a>

- **Comp Cells** [C]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "E coli strain")'>E coli strain</a> / <a href='#' onclick='easy_select("Containers", "E. coli Comp Cell Batch")'>E. coli Comp Cell Batch</a>



### Outputs


- **Transformed E Coli** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Transformed E. coli Aliquot")'>Transformed E. coli Aliquot</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
eval Library.find_by_name("Preconditions").code("source").content
extend Preconditions

def precondition(op) 
    if op.input("Plasmid").object_type.name == "Ligation Product" 
        return time_elapsed op, "Plasmid", hours: 2
    else
        return true
    end
    
    if op.input("Plasmid").sample.properties["Bacterial Marker"].nil? || op.input("Plasmid").sample.properties["Bacterial Marker"] == ""
        return false
    end
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Author: Ayesha Saleem
# November 5, 2016
# Revision: Justin Vrana, 2017-07-21 (corrected index error, refactored collection removal proceedure, added batch replacement, added plasimd stock dilution)
# Revision: Orlando do Lange, 2017-09-12 (Added precondition that if the input is a Ligation product that item must be at least 2 hours old)

needs "Cloning Libs/Special Days"
needs "Standard Libs/Debug"
needs "Standard Libs/Feedback"

class Protocol
  include Feedback
  include SpecialDays
  include Debug
  
  # io
  CELLS = "Comp Cells"
  INPUT = "Plasmid"
  OUTPUT = "Transformed E Coli"
  
  # debug
  DEBUG_WITH_REPLACEMENT = true
  
  # specs
  RESUSPENSION_VOL = 900 # how much to resuspend transformed cells in
    
  def main
    # Detract comp cells from batches, store how many of each type of comp cell there are, and figure out how many Amp vs Kan plates will be needed 
    
    # Determine replacements of e coli comp cell batch
    determine_replacements

    # Detract from running batches
    operations.running.each { |op| op.input(CELLS).collection.remove_one op.input(CELLS).sample }

    # Exit early if there are no more running operations
    if operations.empty?
      show do
        title "All operations have errored"
        note "All operations have errored out."
      end
      return {}
    end
  
    # Make 
    operations.running.retrieve(only: ["Plasmid"]).make
   
    # Prepare electroporator 
    prepare_electroporator
      
    # Measure plasmid stock concentrations
    ops_for_dilution = operations.running.select { |op| op.input(INPUT).object_type.name == "Plasmid Stock" }
    ops_for_measurement = ops_for_dilution.select { |op| op.input(INPUT).item.get(:concentration).to_f == 0.0 }
    measure_plasmid_stock ops_for_measurement

    # Dilute plasmid stocks
    dilute_plasmid_stocks ops_for_dilution
  
    # Get comp cells and cuvettes 
    get_cold_items  
      
    # Label aliquots
    label_aliquots  
      
    index = 0
  
    # Display table to tech
    display_table index
      
    #plate pre heating
    plate_preheating  
    
    # Incubate transformants
    incubate_transformants 

    # Clean up
    clean_up
      
    # Move items
      operations.running.each do |op|
        op.output(OUTPUT).item.move "37C shaker"
      end
      
    give_happy_birthday
      
    # Store dna stocks
      all_stocks = operations.running.map { |op| [op.input(INPUT).item, op.temporary[:old_stock]] }.flatten.uniq
      all_stocks.compact!
      release all_stocks, interactive: true, method: "boxes"
      
    return {}
  end
  
  # This method tells the technician to prepare the electroporator and bench
  def prepare_electroporator
    show do
      title "Prepare bench"
      note "If the electroporator is off (no numbers displayed), turn it on using the ON/STDBY button."
      note "Set the voltage to 1250V by clicking the up and down buttons."
      note " Click the time constant button to show 0.0."
      image "Actions/Transformation/initialize_electroporator.jpg"
      check "Retrieve and label #{operations.running.length} 1.5 mL tubes with the following ids: #{operations.running.collect { |op| "#{op.output(OUTPUT).item.id}"}.join(",")} "
      check "Set your 3 pipettors to be 2 uL, 42 uL, and 900 uL."
      check "Prepare 10 uL, 100 uL, and 1000 uL pipette tips."      
      check "Grab a Bench SOC liquid aliquot (sterile) and loosen the cap."
    end
  end
  
  # takes in array of operations and asks the technician
  # to measure the concentrations of the input items.
  # 
  # @param ops_for_measurement [Array] the ops that contain the items we are measuring
  def measure_plasmid_stock ops_for_measurement
    if ops_for_measurement.any?
      conc_table = Proc.new { |ops|
        ops.start_table
          .input_item(INPUT)
          .custom_input(:concentration, heading: "Concentration (ng/ul)", type: "number") { |op| 
            x = op.temporary[:concentration] || -1
            x = rand(10..100) if debug
            x
          }
          .validate(:concentration) { |op, v| v.between?(0,10000) }
          .validation_message(:concentration) { |op, k, v| "Concentration must be non-zero!" }
          .end_table.all
      }
      
      show_with_input_table(ops_for_measurement, conc_table) do
        title "Measure concentrations"
        note "The concentrations of some plasmid stocks are unknown."
        check "Go to the nanodrop and measure the concentrations for the following items."
        check "Write the concentration on the side of each tube"
      end
      
      ops_for_measurement.each do |op|
        op.input(INPUT).item.associate :concentration, op.temporary[:concentration]
      end
    end
  end
  
  # This method tells the technician to get cold items.
  def get_cold_items  
    show do 
      title "Get cold items"
      note "Retrieve a styrofoam ice block and an aluminum tube rack. Put the aluminum tube rack on top of the ice block."
      image "arrange_cold_block"
      check "Retrieve #{operations.length} cuvettes and put inside the styrofoam touching ice block."
      note "Retrieve the following electrocompetent aliquots from the M80 and place them on an aluminum tube rack: "
      operations.group_by { |op| op.input(CELLS).item }.each do |batch, grouped_ops|
        check "#{grouped_ops.size} aliquot(s) of #{grouped_ops.first.input(CELLS).sample.name} from batch #{batch.id}"
      end
      image "Actions/Transformation/handle_electrocompetent_cells.jpg"
    end
  end
  
  # This method tells the technician to label aliquots.
  def label_aliquots  
    show do 
      title "Label aliquots"
      aliquotsLabeled = 0
      operations.group_by { |op| op.input(CELLS).item }.each do |batch, grouped_ops|
        if grouped_ops.size == 1
          check "Label the electrocompetent aliquot of #{grouped_ops.first.input(CELLS).sample.name} as #{aliquotsLabeled + 1}."
        else
          check "Label each electrocompetent aliquot of #{grouped_ops.first.input(CELLS).sample.name} from #{aliquotsLabeled + 1}-#{grouped_ops.size + aliquotsLabeled}."
        end
        aliquotsLabeled += grouped_ops.size
      end
      note "If still frozen, wait till the cells have thawed to a slushy consistency."
      warning "Transformation efficiency depends on keeping electrocompetent cells ice-cold until electroporation."
      warning "Do not wait too long"
      image "Actions/Transformation/thawed_electrocompotent_cells.jpg"
    end
  end
  
  # This method tells the technician to add plasmid to the electrocompetent aliquot, electroporate, and rescue.
  def display_table index
    show do
      title "Add plasmid to electrocompetent aliquot, electroporate and rescue "
      note "Repeat for each row in the table:"
      check "Pipette 2 uL plasmid/gibson result into labeled electrocompetent aliquot, swirl the tip to mix and place back on the aluminum rack after mixing."
      check "Transfer 42 uL of e-comp cells to electrocuvette with P100"
      check "Slide into electroporator, press PULSE button twice, and QUICKLY add #{RESUSPENSION_VOL} uL of SOC"
      check "pipette cells up and down 3 times, then transfer #{RESUSPENSION_VOL} uL to appropriate 1.5 mL tube with P1000"
      table operations.running.start_table 
        .input_item("Plasmid")
        .custom_column(heading: "Electrocompetent Aliquot") { index = index + 1 }
        .output_item("Transformed E Coli", checkable: true)
        .end_table
    end
  end
  
  # This method tells the technician to incubate the E. coli transformants.
  def incubate_transformants 
    show do 
      title "Incubate transformants"
      check "Grab a glass flask"
      check "Place E. coli transformants inside flask laying sideways and place flask into shaking #{operations[0].input("Plasmid").sample.properties["Transformation Temperature"].to_i} C incubator."
      #Open google timer in new window
      note "Transformants with an AMP marker should incubate for only 30 minutes. Transformants with a KAN, SPEC, or CHLOR marker needs to incubate for 60 minutes."
      note "<a href=\'https://www.google.com/search?q=30%20minute%20timer\' target=\'_blank\'>Use a 30 minute Google timer</a> or <a href=\'https://www.google.com/search?q=60%20minute%20timer\' target=\'_blank\'>a 60 minute Google timer</a> to set a reminder to retrieve the transformants, at which point you will start the \'Plate Transformed Cells\' protocol."
      image "Actions/Transformation/37_c_shaker_incubator.jpg"
      note "While the transformants incubate, finish this protocol by completing the remaining tasks."
    end
  end
  
  # This method tells the technician to pre-heat the plates for later use.
  def plate_preheating  
    show do 
      title "Pre-heat plates"
      note "Retrieve the following plates, and place into still #{operations[0].input("Plasmid").sample.properties["Transformation Temperature"].to_i} C incubator."    
      grouped_by_marker = operations.running.group_by { |op|
        op.input(INPUT).sample.properties["Bacterial Marker"].upcase
      }
      grouped_by_marker.each do |marker, ops|
        check "#{ops.size} LB + #{marker} plates"
      end
      image "Actions/Plating/put_plate_incubator.JPG"
    end
  end
  
  # This method tells the technician to clean up items used in this protocol.
  def clean_up
    show do
      title "Clean up"
      check "Put all cuvettes into biohazardous waste."
      check "Discard empty electrocompetent aliquot tubes into waste bin."
      check "Return the styrofoam ice block and the aluminum tube rack."
      image "Actions/Transformation/dump_dirty_cuvettes.jpg"
    end
  end
  
  # This method determines and finds replacement batches if the current batch is empty.
  # If there are no replacement batches available, that batch's operation errors.
  def determine_replacements
    operations.running.each do |op|
      # If current batch is empty
      if op.input(CELLS).collection.empty? || (debug and DEBUG_WITH_REPLACEMENT)
        old_batch = op.input(CELLS).collection
        
        # Find replacement batches
        all_batches = Collection.where(object_type_id: old_batch.object_type.id).select { |b| !b.empty? && !b.deleted? && (b.matrix[0].include? op.input(CELLS).sample.id) }
        # batches_of_cells = all_batches.select { |b| b.include? op.input(CELLS).sample && !b.deleted? }.sort { |x| x.num_samples }
        batches_of_cells = all_batches.reject { |b| b == old_batch }.sort { |x| x.num_samples } # debug specific rejection to force replacement
        
        # Error if not enough
        if batches_of_cells.empty?
          op.error :not_enough_comp_cells, "There were not enough comp cells of #{op.input(CELLS).sample.name} to complete the operation."
        else
          # Set input to new batch
          
          op.input(CELLS).set collection: batches_of_cells.last
          # Display warning
          op.associate :comp_cell_batch_replaced, "There were not enough comp cells for this operation. Replaced batch #{old_batch.id} with batch #{op.input(CELLS).collection.id}"
        end
      end
    end
  end
  
  # This method tells the technician to dilute plasmid stocks.
  def dilute_plasmid_stocks ops_for_dilution
    if ops_for_dilution.any?
      show do
        title "Prepare plasmid stocks"
        
        ops_for_dilution.each do |op|
          i = produce new_sample op.input(INPUT).sample.name, of: op.input(INPUT).sample_type, as: "1 ng/µL Plasmid Stock"
          
          op.temporary[:old_stock] = op.input(INPUT).item
          op.input(INPUT).item.associate :from, op.temporary[:old_stock].id
          vol = 0.5
          c = op.temporary[:old_stock].get(:concentration).to_f
          op.temporary[:water_vol] = (vol * c).round(1)
          op.temporary[:vol] = vol
          op.input(INPUT).set item: i
          op.associate :plasmid_stock_diluted, "Plasmid stock #{op.temporary[:old_stock].id} was diluted and a 1 ng/ul Plasmid Stock was created: #{op.input(INPUT).item.id}"
        end
        
        check "Grab <b>#{ops_for_dilution.size}</b> 1.5 mL tubes and place in rack"
        note "According to the table below:"
        check "Label all tubes with the corresponding Tube id"
        check "Pipette MG H20"
        check "Pipette DNA"
        table ops_for_dilution.start_table
          .input_item(INPUT, heading: "Tube id", checkable: true)
          .custom_column(heading: "MG H20", checkable: true) { |op| "#{op.temporary[:water_vol]} ul" }
          .custom_column(heading: "Plasmid Stock (ul)", checkable: true) { |op| "#{op.temporary[:vol]} ul of #{op.temporary[:old_stock].id}" }
          .end_table
      end
      
      show do
        title "Set aside old plasmid stocks"
        
        note "The following plasmid stocks will no longer be needed for this protocol."
        check "Set aside the old plasmid stocks:"
        ops_for_dilution.each do |op|
          check "#{op.temporary[:old_stock]}"
        end
      end
    end
  end
end 
```
