# Make Overnight Suspension

This is run after **Check Plate** and is a precursor to **Make Miniprep**. Once the plate with transformed E. coli cells has been checked, the technician will pick out a colony and suspend it in either TB + Amp or TB + Kan. The suspension is then inoculated overnight in the 37 F shaker incubator.
### Inputs


- **Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Checked E coli Plate of Plasmid")'>Checked E coli Plate of Plasmid</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Glycerol Stock")'>Plasmid Glycerol Stock</a>



### Outputs


- **Overnight** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "TB Overnight of Plasmid")'>TB Overnight of Plasmid</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
  true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Note: This change (08/22/2018) reverts back to July 26, 2018 version

needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug"
needs "Standard Libs/Feedback"

class Protocol

  include Feedback    
  include Cloning
  include Debug

  def main
      
    operations.retrieve(interactive: false)
    
    # Increase the number of colonies picked the plate. If no picked number is present,
    # set it equal to one. Note that setting the status to "error" will remove the operation
    # from operations.running, so it will not be listed in tables, etc.
    operations.select { |op| op.input("Plasmid").item.object_type_id == ObjectType.where(name: "Checked E coli Plate of Plasmid").first.id }.each do |op|
       nc = (op.input_data "Plasmid", :num_colonies).to_i
       np = (op.input_data "Plasmid", :num_picked).to_i
       if debug && !nc && rand(2) == 1
         op.set_input_data "Plasmid", :num_colonies, 1
         op.set_input_data "Plasmid", :num_picked, 1
       elsif !nc || nc == 0 || ( np && np >= nc )
         op.error :missing_data, "No colonies left on plate or colony number not defined"
       else
         op.set_input_data "Plasmid", :num_picked, (np || 0) + 1
       end
    end
    
    # Error out operations whose samples don't have bacterial marker data. Tell technician
    # which ones are not being used. Quit if there are no samples left.
    operations.each do |op|
      unless op.input("Plasmid").child_sample.properties["Bacterial Marker"]
        if debug && rand(2) == 1
          op.input("Plasmid").child_sample.set_property "Bacterial Marker", "Amp"
        else
          op.set_status "error"
          op.associate :missing_marker, "No bacterial marker associated with plasmid"
        end
      end
    end
    
    operations.make
    
    p_ot = ObjectType.where(name: "Checked E coli Plate of Plasmid").first 
    
    raise "Could not find object type 'Checked E coli Plate of Plasmid'" unless p_ot
    
    plate_inputs = operations.running.select { |op| op.input("Plasmid").item.object_type_id == p_ot.id }
    
    g_ot = ObjectType.where(name: "Plasmid Glycerol Stock").first 
    
    raise "Could not find object type 'Plasmid Glycerol Stock'" unless g_ot 
    
    glycerol_stock_inputs = operations.running.select { |op| op.input("Plasmid").item.object_type_id == g_ot.id }
    
    overnight_steps plate_inputs, "Checked E coli Plate of Plasmid" if plate_inputs.any?
    overnight_steps glycerol_stock_inputs, "Plasmid Glycerol Stock" if glycerol_stock_inputs.any?
    
    # Associate input id with from data for overnight.
    operations.running.each do |op|
      gs = op.input("Plasmid").item
      on = op.output("Overnight").item
      
      on.associate :from, gs.id
      pass_data "sequencing results", "sequence_verified", from: gs, to: on
    end
    
    operations.running.each do |op|
      op.output("Overnight").child_item.move "37 C shaker incubator"
    end
    
    operations.store
    
    return {}

  end 
  
  # This method sorts operations by the bacterial marker attribute and then
  # starts overnight steps by calling the methods label_load_tubes and inoculate.
  def overnight_steps(ops, ot)
    if ot == "Plasmid Glycerol Stock"
      ops.retrieve interactive: false
    else
      ops.retrieve
    end
    
    # Sorting ops by the bacterial marker attribute
    temp = ops.sort do |op1,op2|
      op1.input("Plasmid").child_sample.properties["Bacterial Marker"].upcase <=> op2.input("Plasmid").child_sample.properties["Bacterial Marker"].upcase
    end
    ops = temp
    
    ops.extend(OperationList)
   
    #Label and load overnight tubes 
    label_load_tubes ops

    #Inoculation
    inoculate ot, ops
      
  end
  
  # Given operations, tells the technician to label and load the tubes the tubes
  def label_load_tubes ops
    show do
      title "Label and load overnight tubes"
      note "In the Media Bay, collect #{ops.length} 14mL tubes"
      note "Write the overnight id on the corresponding tube and load with the correct media type."
      table ops.start_table
        .output_item("Overnight", checkable: true)
        .custom_column(heading: "Media") { |op| "TB+" + op.input("Plasmid").child_sample.properties["Bacterial Marker"].upcase }
        .custom_column(heading: "Quantity") { |op| "3 mL" }
        .end_table
    end
  end
  
  # Tells the technician to inoculate colonies from plate into 14 ml tubes.
  def inoculate ot, ops
    show {
      title "Inoculation from #{ot}"
      note "Use 10 uL sterile tips to inoculate colonies from plate into 14 mL tubes according to the following table." if ot == "Checked E coli Plate of Plasmid"
      check "Mark each colony on the plate with corresponding overnight id. If the same plate id appears more than once in the table, inoculate different isolated colonies on that plate." if ot == "Checked E coli Plate of Plasmid"
      note "Use 100 uL pipette to inoculate cells from glycerol stock into the 14 mL tube according to the following table." if ot == "Plasmid Glycerol Stock"
      table ops.start_table
        .input_item("Plasmid", heading: ot)
        .custom_column(heading: "#{ot} Location") { |op| op.input("Plasmid").item.location }
        .output_item("Overnight", checkable: true)
        .end_table      
    } 
  end
end 
```
