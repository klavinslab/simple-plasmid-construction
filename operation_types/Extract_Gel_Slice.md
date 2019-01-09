# Extract Gel Slice

This is run after **Run Gel** and is a precursor to **Make PCR Fragment**. A gel, after gel electrophoresis has been run, is imaged, and the technician uploads both the gel image and verifies whether or not the fragment matches the expected size. If the fragment is the correct length, the fragment is extracted from the gel; if it isn't, the operation errors out and the fragment is thrown out.


### Inputs


- **Fragment** [F]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "50 mL 0.8 Percent Agarose Gel in Gel Box")'>50 mL 0.8 Percent Agarose Gel in Gel Box</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "50 mL 0.8 Percent Agarose Gel in Gel Box")'>50 mL 0.8 Percent Agarose Gel in Gel Box</a>



### Outputs


- **Fragment** [F]  
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Gel Slice")'>Gel Slice</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Gel Slice")'>Gel Slice</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
    true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Extract Fragment Protocol
# V1.0.2; 2017-07-17 JV
# Written by Ayesha Saleem
# Revised by Justin Vrana 2017-07-13; corrected upload issue
# Revised by Justin Vrana 2017-07-17; unique upload table
needs "Standard Libs/UploadHelper"
needs "Standard Libs/AssociationManagement"
needs "Standard Libs/Feedback"
class Protocol
    include Feedback
    include UploadHelper, AssociationManagement
        
    # I/O
    FRAGMENT="Fragment"
    FRAGMENT_OUT="Fragment"
    
    # upload stuff
    DIRNAME="<where are gel files on computer>"
    TRIES=3
    
    # gel stuff
    MIN_WEIGHT = 0.0
    MAX_WEIGHT = 10.0
    CORRECT=["y","n"] # values for debug

    def main
      
      # Sort operations by gels and columns (these can get out of order from PCR)
      operations.sort! do |op1, op2| 
        fv1 = op1.input(FRAGMENT)
        fv2 = op2.input(FRAGMENT)
        [fv1.item.id, fv1.row, fv1.column] <=> [fv2.item.id, fv2.row, fv2.column]
      end
      
      operations.retrieve(interactive: false)
      
      # get gel images
      gels = operations.map { |op| op.input(FRAGMENT).collection}.uniq
      gels.each { |gel|
    
        grouped_ops=operations.select { |op| op.input(FRAGMENT).collection == gel }
        image_name = "gel_#{gel.id}"
        
        # image gel
        image_gel gel, image_name

        
        # upload image
        ups = uploadData("#{DIRNAME}/#{image_name}", 1, TRIES) # 1 file per gel
        ups = [Upload.find(1)] if debug
        
        # associate to gel, plan, op 
        # can't associate to outputs yet because they are only made if lengths are verified
        up=nil
        if(!(ups.nil?))
          up=ups[0]

          gel_item = Item.find(gel.id)

          # associate gel image to gel
          gel_item.associate image_name, "successfully imaged gel", up
          
          grouped_ops.each do |op| # associate to all operations connected to gel
            # description of where this op is in the gel, to be used as desc tag for image upload
            location_in_gel = "#{op.input(FRAGMENT).sample.name} is in row #{op.input(FRAGMENT).row + 1} and column #{op.input(FRAGMENT).column + 1}"
            
            # associate image to op with a location description
            op.associate image_name, location_in_gel, up
            
            # associate image to plan, or append new location to description if association already exists
            existing_assoc = op.plan.get(image_name)
            if existing_assoc && op.plan.upload(image_name) == up
                op.plan.modify(image_name, existing_assoc.to_s + "\n" + location_in_gel, up)
            else
                op.plan.associate image_name, location_in_gel , up
            end
          end
        end
        
        # check lengths of fragments in gel
        check_frag_length gel, grouped_ops
        # grouped_ops.map { |op| op.temporary[:correct] = CORRECT.rotate!.first } if debug
        
        
        # check whether fragment matched length
        grouped_ops.each { |op|
          if(op.temporary[:correct].upcase.start_with?("N"))
            op.error :incorrect_length, "The fragment did not match the expected length."
          end
        }
        
        # get grouped_ops that have not errored
        
        grouped_ops.select! { |op| op.status == "running"  }

        # show { note "Making the following ops: #{grouped_ops.map { |op| op.id }}"}
        grouped_ops.make    # contains only running ops from here on !!!
        # show { note "#{grouped_ops.map { |op| op.output(FRAGMENT_OUT).item }}" }

        
        if(grouped_ops.any?)
          # cut fragments
          cut_fragments grouped_ops  

          # weigh fragments
          weigh_fragments grouped_ops
         
          # associate gel image, fragment lane with fragment and weight with the gel slices to output
          grouped_ops.each { |op|
            op.output(FRAGMENT_OUT).item.associate(image_name, "Your fragment is in row #{op.input(FRAGMENT).row + 1} and column #{op.input(FRAGMENT).column + 1}", up) 
            op.output(FRAGMENT_OUT).item.associate(:weight, op.temporary[:weight]) 
          }
          
        else 
          # do we want this? ask cami/sam
          show {
            title "Your lucky day!"
            note "No fragments to extract from gel #{gel}."
          }
        end # grouped_ops.any?
        
        # clean up after gel
        clean_up gel, gels
        
        # delete collection
        gel.mark_as_deleted
          
      } # gels.each
      
      ok_ops=operations.running
      operations=ok_ops
  
      # are we cleaning from gel now?
      choice = show {
        title "What Next?"
        select ["Yes", "No"], var: "choice", label: "Would you like to purify the gel slices immediately?", default: 0
      }
      plans = operations.map { |op| op.plan }.uniq
      plans.each { |plan|
        plan.associate :choice, choice[:choice]
      }
      if(choice[:choice] == "Yes")
        show {
          title "Keep Gel Slices"
          note "Keep the gel slices #{operations.map{ |op| op.output(FRAGMENT_OUT).item}.to_sentence} on your bench to use in the next protocol."
        }
      else
        operations.store
      end
      
      get_protocol_feedback
      return {}
    end
    
    # This method instructs the technician to image the given gel.
    def image_gel gel, image_name
      show do
        title "Image gel #{gel}"
        check "Clean the transilluminator with ethanol."
        check "Put the gel #{gel} on the transilluminator."
        check "Turn off the room lights before turning on the transilluminator."
        check "Put the camera hood on, turn on the transilluminator and take a picture using the camera control interface on computer."
        check "Check to see if the picture matches the gel before uploading."
        check "Rename the picture you just took exactly as <b>#{image_name}</b>."
      end
    end
    
    # This method tells the technician to verify fragment lengths for the given gel.
    def check_frag_length gel, grouped_ops
      show {
        title "Verify Fragment Lengths for gel #{gel}"
        table grouped_ops.start_table
          .custom_column(heading: "Gel ID") { |op| op.input(FRAGMENT).item.id }
          .custom_column(heading: "Row") { |op| op.input(FRAGMENT).row + 1 }
          .custom_column(heading: "Column", checkable: true) { |op| op.input(FRAGMENT).column + 1 }
          .custom_column(heading: "Expected Length") { |op| op.output(FRAGMENT_OUT).sample.properties["Length"] }
          .get(:correct, type: 'text', heading: "Does the band match the expected length? (y/n)", default: 'y')
          .custom_column(heading: "User") { |op| op.user.name }
          .custom_column(heading: "Fragment Name") { |op| op.output(FRAGMENT_OUT).sample.name }
        .end_table
      }
    end   
    
    # This method instructs the technician to cut out fragments associated to the given operations.
    def cut_fragments grouped_ops  
      show {
        title "Cut Out Fragments"
        note "Take out #{grouped_ops.length} 1.5 mL tubes and label accordingly: #{grouped_ops.map { |op| "#{op.output("Fragment").item}" }.to_sentence}"
        note "Now, cut out the bands and place them into the 1.5 mL tubes according to the following table:"
        table grouped_ops.start_table 
          .custom_column(heading: "Gel ID") { |op| "#{op.input(FRAGMENT).item}" }
          .custom_column(heading: "Row") { |op| op.input(FRAGMENT).row + 1 }
          .custom_column(heading: "Column", checkable: true) { |op| op.input(FRAGMENT).column + 1 }
          .custom_column(heading: "1.5 mL Tube ID") { |op| "#{op.output(FRAGMENT_OUT).item}" }
          .custom_column(heading: "Length") { |op| op.output(FRAGMENT_OUT).sample.properties["Length"] }
        .end_table
      }
    end
    
    # This method instructs the technician to weigh gel slices.
    def weigh_fragments grouped_ops
      show {
        title "Weigh Gel Slices"
        note "Perform this step using the scale inside the gel room."
        check "Zero the scale with an empty 1.5 mL tube."
        check "Weigh each slice and enter the weights in the following table:"
        table grouped_ops.start_table
          .custom_column(heading: "1.5 mL Tube ID") { |op| "#{op.output(FRAGMENT_OUT).item}" }
          .get(:weight, type: 'number', heading: "Weight (g)",  default: MIN_WEIGHT)
          .end_table
      }
    end
    
    # This method instructs the technician to clean up and dispose of gels.
    def clean_up gel, gels
      show {
        title "Clean Up"
        check "Turn off the transilluminator."
        check "Dispose of the gel #{gel} and any gel parts by placing it in the waste container. Spray the surface of the transilluminator with ethanol and wipe until dry using a paper towel."
        check "Clean up the gel box and casting tray by rinsing with water. Return them to the gel station."
        if(gel==gels.last)
            check "Dispose gloves after leaving the room."
        end
      }
    end
end
```
