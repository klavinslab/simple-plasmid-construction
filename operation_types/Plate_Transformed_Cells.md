# Plate Transformed Cells

This is run after **Transform Cells** and is a precursor to **Check Plate**. The transformed E. coli cells are plated on either LB + Amp or LB + Kan and incubated at 37 F.
### Inputs


- **Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Transformed E. coli Aliquot")'>Transformed E. coli Aliquot</a>



### Outputs


- **Plate** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "E coli Plate of Plasmid")'>E coli Plate of Plasmid</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
   true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Author: Ayesha Saleem
# December 23, 2016

# TO DO 
    # Fire different antibiotic plate depending on which antibiotic it is (e.g., Amp: 30 min, Kan: 1 hr, etc.)
needs "Standard Libs/Feedback"
class Protocol
  include Feedback
  
  def name_initials str
    full_name = str.split
    begin
      cap_initials = full_name[0][0].upcase + full_name[1][0].upcase
    rescue
      cap_initials = ""
    end
    return cap_initials
  end
  
  def grab_plates plates, batch_num, ids, k
    show do
      title "Grab #{plates.length} of #{k} plates"
      note "Grab #{plates.length} plates from batch #{batch_num.join("and")}"
      check "Label the top of the plates with your intials, the date, and the following ids: #{ids.join(", ")}"
    end
  end

  def plate_transformed_aliquots k, aliquots, plates
    show do 
      title "Plate transformed E coli aliquots"
      check "Use sterile beads to plate THE ENTIRE VOLUME (~200 uL) from the transformed aliquots (1.5 mL tubes) onto the plates, following the table below."
      warning "Note the change in plating volume!"
      check "Discard used transformed aliquots after plating."
      table [["1.5 mL tube", "#{k} Plate"]].concat(aliquots.zip plates)
    end
  end
  
  def spin_tubes
    show do
      title "Spin down tubes and resuspend"
      check "Remove the transformed cells in 1.5 mL tubes from the 250 mL flask."
      check "Centrifuge for 4,000 x g for 1 minute."
      check "Carefully remove most of the supernatant using a P1000 pipette. Leave 200uL of supernatant in each tube."
      check " Resuspend the cells in the remaining supernatant by vortexing."
    end
  end
     
  def group_plates_and_aliquots markers_new
    operations.each do | op | 
      p = op.input("Plasmid").item
      marker_key = "LB"
      p.sample.properties["Bacterial Marker"].split(/[+,]/).each do |marker|
        marker_key = marker_key + " + " + marker.strip[0, 3].capitalize
      end
      
      if Sample.find_by_name(marker_key)
        markers_new[marker_key][p] = op.output("Plate").item
      else
        show do 
          note "#{marker_key}"
        end
        op.error :no_marker, "There is no marker associated with this sample, so we can't plate it. Please input a marker."
      end
    end
    markers_new
  end  
  
  def calculate_and_operate markers
    markers.each do | k, v| 
      aliquots = []
      plates = []
      ids = []
        
      v.each do | al, pl|
        ids.push("#{pl.id} " + name_initials(pl.sample.user.name))
        aliquots.push(al.id)
        al.mark_as_deleted
        plates.push(pl.id)
        pl.location = "#{operations[0].input("Plasmid").sample.properties["Transformation Temperature"]} C incubator"
      end
        
      b = Collection.where(object_type_id: ObjectType.find_by_name("Agar Plate Batch").id)
                        .select { |b| !b.empty? && !b.deleted? && (b.matrix[0].include? Sample.find_by_name(k).id) }.first

      if b.nil? # no agar plate batches exist
        raise "No agar plate batches for #{k} could be found in the Inventory. Pour some plates before continuing (Manager/Pour Plates)"
      end
      batch_num = [b.id]
      n = b.num_samples
      num_p = plates.length
      if n < num_p
        num_p = num_p - n
        b.apportion 10, 10
        b = Collection.where(object_type_id: ObjectType.find_by_name("Agar Plate Batch").id)
                      .select { |b| !b.empty? && !b.deleted? && (b.matrix[0].include? Sample.find_by_name(k).id) }.first
        n = b.num_samples
        batch_num.push(b.id)
      end
          
        m = b.matrix
        x = 0
    
        (0..m.length-1).reverse_each do |i|
          (0..m[i].length-1).reverse_each do |j|
            if m[i][j] != -1 && x < num_p
              m[i][j] = -1
              x += 1
            end
          end
        end
        
        # Grab and label plates
        grab_plates plates, batch_num, ids, k
        
        # Spin down tubes and resuspend
        spin_tubes
        
        # Plate transformed E. coli aliquots
        plate_transformed_aliquots k, aliquots, plates
    end
  end
    
  def main
    operations.retrieve.make
    markers_new = Hash.new { | h, k | h[k] = {} } 
    
    # group plates + transformed aliquots 
    markers = group_plates_and_aliquots markers_new
      
    # tell tech to grab x amount of plates and plate the aliquots
    # also detract from plate batches
    calculate_and_operate markers
    operations.store(io: "output", interactive: true)
    
    get_protocol_feedback
    return {}
    
  end

end
```
