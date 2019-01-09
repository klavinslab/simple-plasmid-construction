# Clean Up Sequencing

**If you are not a lab manager, please DO NOT submit this!**

This protocol does one of three things, depending on user response to sequencing results:
- "Yes": Discard plate.
- "Resequence": Do nothing.
- "No": Discard plasmid stock.
### Inputs


- **Stock** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>

- **Plate** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Checked E coli Plate of Plasmid")'>Checked E coli Plate of Plasmid</a>





### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
eval Library.find_by_name("Cloning").code("source").content
extend Cloning

def precondition(op)
    # return true if response provided for sequencing results
    if op.plan
        # check plan associations
        response = plan.get(plan.associations.keys.find { |key| key.include? "#{op.input("Stock").item.id} sequencing ok?" })
        if response.present? &&
           (response.downcase.include?("yes") || response.downcase.include?("resequence") || response.downcase.include?("no")) &&
           !(response.downcase.include?("yes") && response.downcase.include?("no"))
           
            # Set plasmid stock and overnight to sequence-verified
            stock = op.input("Stock").item
            stock.associate :sequence_verified, "Yes"
            if stock.get(:from) && response.downcase.include?("yes")
                overnight = Item.find(stock.get(:from).to_i)
                pass_data "sequencing results", "sequence_verified", from: stock, to: overnight
            end
            
            return true
        end
    end
end

```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
class Protocol
    
  # This method asks the technician if the sequencing of an operation's id is good or not
  # and acts based on the response. If the sequencing is not good, that operation fails.
  def gather_user_responses
    operations.select { |op| op.plan.get("Item #{op.input("Stock").item.id} sequencing ok?") }.each do |op|
        ans = op.plan.get("Item #{op.input("Stock").item.id} sequencing ok?").downcase
        if ans.include? "yes"
            op.plan.associate "seq_notice_#{op.input("Stock").item.id}".to_sym, "Plate #{op.input("Plate").item.id} has been discarded."
            
            op.temporary[:yes] = true
        elsif ans.include? "resequence"
            op.plan.associate "seq_notice_#{op.input("Stock").item.id}".to_sym, "Plasmid stock not verified; please resubmit this stock for sequencing."
            
            op.temporary[:resequence] = true
        else
            op.plan.associate "seq_notice_#{op.input("Stock").item.id}".to_sym, "Plasmid stock #{op.input("Stock").item.id} has been discarded."
            
            op.temporary[:no] = true
        end
    end
  end
  
  # This method tells the technician to discard plates from the good sequencing
  # results and then deletes those plates from Aquarium's inventory.
  def discard_plates
    show do 
        title "Discard plates from good sequencing results"
        
        note "Please discard the following plates: "
        operations.select { |op| op.temporary[:yes] }.each do |op|
            pl = op.input("Plate").item
            note "Plate #{pl.id} at #{pl.location}"
            pl.mark_as_deleted
            pl.save
        end
    end
  end
  
  # This method tells the technician to discard plates from the bad
  # sequencing results and then deletes those plates from Aquarium's inventory.
  def discard_stocks
    show do
        title "Discard Plasmid Stocks from bad sequencing results"
        
        note "Please discard the following Plasmid Stocks:"
        operations.select { |op| op.temporary[:no] }.each do |op|
            stock = op.input("Stock").item
            note "Plasmid Stock #{stock.id} at #{stock.location}"
            stock.mark_as_deleted
            stock.save
        end
    end 
  end
  
  def main

    # debuggin'
    if debug
        operations.each do |op| 
            op.plan.associate "Item #{op.input("Stock").item.id} sequencing ok?", ["yes somestuff", "no foo", "resequence bar"].sample
        end
    end

    operations.retrieve interactive: false 
    
    # Gather user responses
    gather_user_responses

    # Discard plates for yes
    discard_plates if operations.any? { |op| op.temporary[:yes] }

    # Discard plasmid stocks for no
    discard_stocks if operations.any? { |op| op.temporary[:no] }

    
    return {}
    
  end

end
```
