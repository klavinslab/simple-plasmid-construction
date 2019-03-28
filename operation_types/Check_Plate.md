# Check Plate

Checks plates for growth and contamination.

The plates are pulled from the 37 F incubator and checked for growth and contamination. If there is no growth, the plate is thrown out and the user is notified.

Ran the day after **Plate Transformed Cells** and is a precursor to **Make Overnight Suspension**.
### Inputs


- **Plate** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "E coli Plate of Plasmid")'>E coli Plate of Plasmid</a>



### Outputs


- **Plate** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Checked E coli Plate of Plasmid")'>Checked E coli Plate of Plasmid</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
eval Library.find_by_name("Preconditions").code("source").content
extend Preconditions

def precondition(op) 
  time_elapsed op, "Plate", hours: 8
  true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Author: Ayesha Saleem
# December 20, 2016

# TO DO: 
    # Create option for "there are baby colonies but they're not big enough for protocols" case--put back in incubator
    # Re-streak the plate if there's too much contamination--fire check plate again in 24 hrs, probably collection
needs "Standard Libs/Feedback"
class Protocol
  include Feedback
  def main
    # Take plates  
    operations.retrieve
    
    # Count the number of colonies
    info = get_colony_numbers
    
    # Update plate data
    update_item_data info
    
    # Delete and discard any plates that have 0 colonies
    discard_bad_plates if operations.any? { |op| op.temporary[:delete] }
    
    # Parafilm and label plates 
    parafilm_plates
    
    # Return plates
    operations.store
    
    # Get feedback
    get_protocol_feedback()
    return {}
  end
  
  
  
  # Count the number of colonies and select whether the growth is normal, contaminated, or a lawn
  def get_colony_numbers
    show do
      title "Estimate colony numbers"
      
      operations.each do |op|
        plate = op.input("Plate").item
        get "number", var: "n#{plate.id}", label: "Estimate how many colonies are on #{plate}", default: 5
        select ["normal", "contamination", "lawn"], var: "s#{plate}", label: "Choose whether there is contamination, a lawn, or whether it's normal."
      end
    end    
  end
  
  # Alter data of the virtual item to represent its actual state
  def update_item_data info
    operations.each do |op|
      plate = op.input("Plate").item
      if info["n#{plate.id}".to_sym] == 0
        plate.mark_as_deleted
        plate.save
        op.temporary[:delete] = true
        op.error :no_colonies, "There are no colonies for plate #{plate.id}"
      else
        plate.associate :num_colonies, info["n#{plate.id}".to_sym]
        plate.associate :status, info["s#{plate.id}".to_sym]
        
        checked_ot = ObjectType.find_by_name("Checked E coli Plate of Plasmid")
        plate.store if plate.object_type_id != checked_ot.id
        plate.object_type_id = checked_ot.id
        plate.save
        op.output("Plate").set item: plate
        
        op.plan.associate "plate_#{op.input("Plate").sample.id}", plate.id
      end
    end
  end
  
  # discard any plates that have 0 colonies
  def discard_bad_plates
      show do 
        title "Discard Plates"
        
        discard_plate_ids = operations.select { |op| op.temporary[:delete] }.map { |op| op.input("Plate").item.id }
        note "Discard the following plates with 0 colonies: #{discard_plate_ids}"
    end
  end
  
  # Parafilm and label any plates that have suitable growth
  def parafilm_plates
    show do 
      title "Label and Parafilm"
      
      plates_to_parafilm = operations.reject { |op| op.temporary[:delete] }.map { |op| op.input("Plate").item.id }
      note "Perform the steps with the following plates: #{plates_to_parafilm}"
      note "Label the plates with their item ID numbers on the side, and parafilm each one."
      note "Labelling the plates on the side makes it easier to retrieve them from the fridge."
    end
  end
end
```
