# Assemble Plasmid

This is run after **Make PCR Fragment** (if the fragment is not already in inventory) and is a precursor to **Transform Cells**. The technician combines the inputted array of fragments and, using Gibson Assembly, assembles a plasmid. Each Gibson reaction is fixed at a volume of 5 uL, and so the volume of each fragment is calculated using an algorithm that takes in the number of total fragments in the Gibson reaction and the concentration in ng/uL of each individual fragment. The lower bounds for volume is 0.2 uL; if any fragment is below 0.2 uL, or if the overall reaction is greater than 5 uL, the volumes are tweaked for each fragment until the reaction is once more balanced. The reaction is then placed on a 42 F heat block for one hour.
### Inputs


- **Fragment** [F] (Array) 
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>



### Outputs


- **Assembled Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Gibson Reaction Result")'>Gibson Reaction Result</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
    
    if op.input_array("Fragment").length < 2
        op.error :more_fragments, "You usually shouldn't do a gibson assembly with less than 2 fragments. Was this intentional?"
        return true
    end
    
    
    op.input_array("Fragment").each do |f|
        if f.sample.properties["Length"] == 0.0
            op.error :need_fragment_length, "Your fragment #{f.sample.name} needs a valid length for assembly."
            
            return false
        end
    end
    
    return true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Author: Ayesha Saleem
# December 20, 2016

require 'matrix'
needs "Cloning Libs/Special Days"
needs "Cloning Libs/Cloning"
needs "Standard Libs/Feedback"
# For calculating equimolar concentrations, Yaoyu has written up a great explanation: 

    # math behind the equimolar volume calculation
    # Assume that there are n fragment stocks, each with concentrations c1,..., cn, and lengths l1,...,ln. The volumes of each fragment stocks to add in the Gibson reaction is denoted as v1,...,vn. Assuming that the molecular weight (g/mol) of the fragment is proportional to the lenght of the fragment, to ensure equimolar of these n fragment stocks, the following must satisfy:
    # v1 + ... + vn = 5 (the total gibson reaction volume)
    # v1 * c1 / l1 = ... = vn * cn / ln (they're equimolar)
    # unit of v is uL, unit of c is g/uL, unit of l1 (molecular weight) is g/mol
    # thus v * c / l represent the moles of the fragment stock, and esuring v1 * c1 / l1 = ... = vn * cn / ln lead to equimolar fragment stocks.
    # These mathmatical constraints can be reformated as:
    # v1 + ... + vn = 5
    # v1 * c1 / l1 - v2 * c2 / l2 = 0
    # v1 * c1 / l1 - v3 * c3 / l3 = 0
    #          ...
    # v1 * c1 / l1 - vn * cn / ln = 0
    # The following matrix equations hold:
    # coefficient_matrix * fragment_volumes = total_vector,
    # where 
    # coefficient_matrix = [
    # [1, 1, ..., 1]
    # [c1 / l1, -c2 / l2, ..., 0]
    # [c1 / l1, 0, - c3 / l3 ..., 0]
    # ...
    # [c1 / l1, 0, ..., - vn * cn / ln]
    # ]  (n x n matrix)
    # fragment_volumes = [[v1], [v2], ..., [vn]] (n x 1 matrix)
    # total_vector = [[5], [0], ..., [0]] (n x 1 matrix)
    # matrix multiplication
    # coefficient_matrix.inv * coefficient_matrix * fragment_volumes = coefficient_matrix.inv * total_vector
    # Therefore we have
    # fragment_volumes = coefficient_matrix.inv * total_vector

# NEED TO TEST: 
    # ensuring volume
    # replacing fragment stock

class Protocol
    include Cloning, Feedback, SpecialDays
    debug = false
    
    # this builds a matrix with 1's in the first row
    # the concentration over length (c / l) of the fragment when row = column
    # (with alternating sign) and 0's everywhere else
    def main
        
        # Check for valid fragment lengths
        operations.each do |op|
          fragments_fv = op.input_array("Fragment")
          fragments_fv.each do |fragment|
              if fragment.item.sample.properties["Length"].nil?
                  op.error :invalid_length, "This fragment's length is not valid."
              end
          end
        end
        
        # Take fragments
        operations.retrieve
        operations.make

        check_concentration operations, "Fragment"
        
        temp = operations.running
        operations = temp
        
        #TODO: refactor gibson batch finding algorithm, gib_batch instantiation is uneccessarily long
        # determine which batches to grab gibson aliquots from
        gib_batch = Collection.where(object_type_id: ObjectType.find_by_name("Gibson Aliquot Batch").id).where('location != ?', "deleted").first
        if gib_batch.nil?
            operations.each { |op| op.error :not_enough_gibson, "There were not enough gibson aliquots to complete the operation." }
            raise "not enough gibson"
        end
        batch_id_array = [gib_batch.id]
        total_aliquots = gib_batch.num_samples
        aliquots_needed = operations.length
        i = 0
        while total_aliquots < aliquots_needed
            gib_batch.mark_as_deleted 
            i += 1
            gib_batch = Collection.where(object_type_id: ObjectType.find_by_name("Gibson Aliquot Batch").id).where('location != ?', "deleted").first
            if gib_batch.nil?
                operations.each { |op| op.error :not_enough_gibson, "There were not enough gibson aliquots to complete the operation." }
                raise "Aquarium cannot find any gibson aliquot batches in the system"
            end
            batch_id_array.push(gib_batch.id)
            total_aliquots += gib_batch.num_samples
        end
    
        #fetch gibson aliquots
        get_gibson_aliquots batch_id_array
        
        # Go through and pipette fragments into aliquots
        to_discard = []
        
        # Keep track of fragment stocks to return on errored ops.
        to_return = [];
        
        operations.each do |op|# calculate how much of each fragment is needed in aliquot
          tot_f_vol, f_vol = calc_gibson_volumes op
          vol_table = [["Fragment Stock IDs", "Volume"]].concat(op.input_array("Fragment").items.collect { |f| f.id}.zip f_vol.map { |v| { content: v, check: true }})
          
          # ask tech if there is enough volume
          vol_checking = show do 
            title "Checking Volumes"
            tot_f_vol.each do |id, v|
                select ["Yes", "No"], var: "v#{id}", label: "Does #{id} have at least #{v} uL?", default: 0
            end
          end
          
          # find replacements
          replacement = {}
          
          tot_f_vol.each do |id, v|
              if vol_checking["v#{id}".to_sym] == "No"
                  find_replacements replacement, to_discard, id, v
              end
          end
          
          # associate replacements with operation inputs
          find_replacement = []
          associate_replacements find_replacement, replacement, op
          
          if op.status != "error"
            # take find_replacement, interactive: true if find_replacement.any?
            check_concentration [op], "Fragment"
            
            #feature addition: make an extra column for this table to show whether a p2 pipette is required depending on if vol < 0.5
            if find_replacement.any?
              tot_f_vol, f_vol = calc_gibson_volumes op
              vol_table = [["Fragment Stock IDs", "Volume"]].concat(op.input_array("Fragment").items.collect { |f| f.id}.zip f_vol.map { |v| { content: v, check: true }})
            end
            load_gibson_reaction op, vol_table
          else
              
            # Keep track of what items need to be returned in the case of an error.
            current_fv = op.input_array("Fragment")
            current_fv.each do |fv|
                if fv.item.location != "deleted"
                    to_return.push(fv.item)
                end
            end
            
            show do
              title "Gibson canceled"
              note "Sorry it had to be this way. :/"
            end
          end
        end
    
        # put on heat block
        heat_block
        
        #return gibson aliquots
        data = return_gibson_aliquots aliquots_needed, batch_id_array
        aliquots_returned = data[:n]
        
        #updating gibson batches
        gibsons_used = aliquots_needed - aliquots_returned.to_i
        update_gibson_batches gibsons_used, batch_id_array
  
        # return aluminum tube rack, ice block
        return_aluminumTubeRack_and_iceBlock
        
        # return fragments
        release(to_return, interactive: true)
        operations.store(io: "input", interactive: true, method: "boxes")
        
        show do
          title "Discard depleted stocks"
          note "Discard the following stocks: #{to_discard.map { |s| s.id }}"
        end if to_discard.any?
        
        get_protocol_feedback()
        give_happy_birthday
          
    return {}
  end
  
    def gibson_coefficients row, col, conc_over_length
      # TODO fix this commented out section (only causes error when not debugging)
      # if !debug
        if row == 0
          return 1
        elsif col == 0
          return conc_over_length[0]
        elsif row == col
          return -conc_over_length[row]
        else
          return 0
        end
      # end
    end

    # this creates the "total_volume" row vector
    def gibson_vector row
      if row == 0
        return 5.0
      else
        return 0
      end
    end
    
    def calc_gibson_volumes op
      tot_f_vol = Hash.new(0)
      
      conc_over_length = op.input_array("Fragment").items.collect { |f| f.get(:concentration).to_f  / f.sample.properties["Length"]}
      
      n = conc_over_length.length
      total_vec = Matrix.build(n, 1) { |r, c| gibson_vector r }
      coef_m = Matrix.build(n, n) { |r, c| gibson_coefficients r, c, conc_over_length }
      vol_vec = (coef_m.inv * total_vec).each.to_a.collect! { |x| x.round(2) }
      f_vol = vol_vec.each.to_a.collect! { |x| x < 0.20 ? 0.20 : x }
      
      # this is to ensure that the rxn isn't > 5uL
      max = f_vol.max
      total = f_vol.reduce(:+)
      f_vol[f_vol.index(max)] = (max - (total - 5)).round(2) if total > 5
      
      # collect all volumes to ask tech if enough stock is present 
      op.input_array("Fragment").items.each_with_index do |f, i|
        tot_f_vol[f.id] = f_vol[i]
      end
      
      return tot_f_vol, f_vol
    end

  
  def heat_block
    if operations.running.any?
        show do 
            title "Put Reactions on Heat Block"
            warning "Vortex and spin all Gibson Reactions before putting them on the heat block!"
            note "Put all #{operations.length} on the 50 C heat block"
            note"<a href='https://www.google.com/search?q=1+hr+timer&oq=1+hr+timer&aqs=chrome..69i57j0l5.1684j0j7&sourceid=chrome&es_sm=122&ie=UTF-8#q=1+hour+timer' target='_blank'>
                Set a 1 hr timer on Google</a> to set a reminder to start the ecoli_transformation protocol and retrieve the Gibson Reactions."
        end
    end
  end
  
  def find_replacements replacement, to_discard, id, v
    f = Item.find(id)
    replacement[f.id] = f
    is_bad_replacement = true
    
    # Keep finding replacements if previous replacement doesn't have enough volume
    while(is_bad_replacement)
        to_discard.push replacement[f.id]
        replacement[f.id].move_to("deleted")
        replacement[f.id].save 
        replacement[f.id] = Item.where(sample_id: f.sample_id).where(object_type_id: f.object_type_id).where("location != ?", "deleted").to_a.first
        # Only do this if there exists a replacement
        # has the tech confirm if the new replacement has enough volume
        if replacement[f.id]
            loop_check = show do
                title "Find replacements"
                note "Retrieve #{replacement[f.id].id} from #{replacement[f.id].location}"
                select ["Yes", "No"], var: "v#{id}", label: "Does #{replacement[f.id].id} have at least #{v} uL?", default: 0
            end
            is_bad_replacement = !(loop_check["v#{id}".to_sym] == "Yes")
        else #exit the loop if there are no replacements available
            show do
                title "We couldnt find replacements."
            end
            is_bad_replacement = false;
        end
    end   
  end
  
  def get_gibson_aliquots batch_id_array
    show do
        title "Grab Gibson aliquots"
        note "Grab an ice block and aluminum tray from the fridge"
        note "Grab #{operations.length} Gibson aliquots from batch#{"es" if batch_id_array.length > 1} #{batch_id_array}, located in the M20"
    end
  end
  
  def load_gibson_reaction op, vol_table
    show do
      title "Load Gibson Reaction #{op.output("Assembled Plasmid").item.id}"
      note "Label an unused aliquot with #{op.output("Assembled Plasmid").item.id}"
      note "Make sure the Gibson aliquot is thawed before pipetting"
      warning "Please use the P2 for any volumes below 0.5 uL"
      table vol_table
    end
  end  
  
  def return_aluminumTubeRack_and_iceBlock
    show do
      title "Return ice block and aluminum tube rack"
      check "Return the ice block and aluminum tube rack."
      check "discard the used up gibson aliquot batch."
    end    
  end
  
  def return_gibson_aliquots aliquots_needed, batch_id_array
    data = show do
        title "Return unused gibson aliquots"
        note "#{aliquots_needed} aliquots were needed for this protocol, but you might have not used all of them."
        note "Return any unused aliquots to batch#{"es" if batch_id_array.length > 1} #{batch_id_array.reverse} in the M20"
        get "number", var: "n", label: "How many gibson aliquots will be returned?", default: "0"
        note "If you used more aliquots than predicted, indicate with a negative value."
    end
    data #return
  end
  
  def associate_replacements find_replacement, replacement, op
    replacement.each do |id, item|

      if item

        op.input_array("Fragment").find { |fv| fv.item.id == id }.set item: item
        find_replacement.push(item)
      else
        op.error :volume, "Insufficient fragment stock volume for Gibson reaction." 
        break
      end
    end
  end
  
    def update_gibson_batches gibsons_used, batch_id_array
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
