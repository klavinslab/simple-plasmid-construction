# Pour Gel

Pours a a mixture composing of a gel and GelGreen into a casting tray.

In this protocol, a gel is poured into a flask and is then GelGreen
is added to it. Finally, the gels get poured into a casting tray and then gets labeled on the side of
the gel box.

Is a precursor to **Run Gel**. 




### Outputs


- **Lane** [G]  Part of collection
  - NO SAMPLE TYPE / <a href='#' onclick='easy_select("Containers", "50 mL 0.8 Percent Agarose Gel in Gel Box")'>50 mL 0.8 Percent Agarose Gel in Gel Box</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
    if op.plan
      pcrs = op.plan.operations.select { |o|
          o.operation_type.name == "Make PCR Fragment"
      }
      pcrs.length == 0 || pcrs[0].status == 'done'
    else
      true
    end
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
needs "Standard Libs/Feedback"
class Protocol
  include Feedback
  def main
    num_ops = operations.length
    o = operations.first.output("Lane").object_type
    lanes_per_gel = o.rows * o.columns
    
    gels_needed = ( num_ops / 8.0 ).ceil # since four lanes are reserved for ladder
    
    ladder_lanes = ( num_ops / 4.0 ).ceil # since four lanes are reserved for ladder
    
    volume = 35.0
    percentage = 1.0
    mass = ((percentage / 100) * volume).round 2
    error = ( mass * 0.05 ).round 5 
    
    #insert virtual operations at 0, 6, 12, 18, ...
    (0...ladder_lanes).each do |l|
       insert_operation 6*l, VirtualOperation.new
       insert_operation 6*l + 1, VirtualOperation.new
    end
    
    operations.make
    
    # Add the top and bottom combs
    top_bottom_combs
    
    # Given the number of gels needed, mass, and margin of error, pour gels
    pour_gels gels_needed, mass, error
    
    # Add GelGreen
    add_gel_green 
    
    # Pour and label the gels
    pour_label_gels
    
    operations.store(io: "output") 
    #get_protocol_feedback
    return {}
    
  end
  
  # Instructs the technician to set up the gel box and add top and bottom combs.
  def top_bottom_combs
    show do
      title "Set up gel box, and add top and bottom combs"
      check "Set up a 49 mL Gel Box With Casting Tray (clean)"
      check "Retrieve two 6-well purple combs from A7.325"
      check "Position the gel box with the electrodes facing away from you. Add a purple comb to the side and center of the casting tray nearest the side of the gel box."
      check "Put the thick side of the comb down."
      note "Make sure the comb is well-situated in the groove of the casting tray."
      # image "gel_comb_placement"
    end      
  end
  
  # Tells the technician to mix agarose powder and 1X TAE in a graduated cylinder.
  def pour_gels gels_needed, mass, error
    show do
      title "Pour #{gels_needed} gel(s)"
      check "Grab a flask from on top of the microwave M2."
      check "Using a digital scale, measure out #{mass} g (+/- #{error} g) of agarose powder and add it to the flask."
      check "Get a graduated cylinder from on top of the microwave. Measure and add 50 mL of 1X TAE from jug J2 to the flask."
      check "Microwave 70 seconds on high in microwave M2, then swirl. The agarose should now be in solution."
      note "If it is not in solution, microwave 7 seconds on high, then swirl. Repeat until dissolved."
      warning "Work in the gel room, wear gloves and eye protection all the time"
    end
  end
  
  # Tells the technician to add GelGreen to each gel.
  def add_gel_green
    show do
      title "For each gel, Add 5 µL GelGreen"
      note "Using a 10 µL pipetter, take up 5 µL of GelGreen into the pipet tip. Expel the GelGreen directly into the molten agar (under the surface), then swirl to mix."
      warning "GelGreen is supposedly safe, but stains DNA and can transit cell membranes (limit your exposure)."
      warning "GelGreen is photolabile. Limit its exposure to light by putting it back in the box."
      # image "gel_add_gelgreen"
    end
  end
  
  # Tells the technician to pour and label each gel.
  def pour_label_gels
    show do
      title "Pour and label the gel(s)"
      note "Using a gel pouring autoclave glove, pour agarose from one flask into the casting tray. 
            Pour slowly and in a corner for best results. Pop any bubbles with a 10 µL pipet tip. Repeat for each gel"
      operations.output_collections["Lane"].each_with_index do | gel, i |
          check "Write id #{gel.id} on piece of lab tape and affix it to the side of the gel box."
      end
      note "Leave the gel to solidify."
      # image "gel_pouring"
    end
  end

end

```
