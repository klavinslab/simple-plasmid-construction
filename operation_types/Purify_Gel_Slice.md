# Purify Gel Slice

This protocl is run after *Extract Fragment* and before *Make PCR Fragment*. It dissolves the
extracted gel slice in a QG Buffer and purifies the fragment on a spin column. It then tells
the technician to determine the concentration using a Nanodrop and to record it.
### Inputs


- **Gel** [F]  
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Gel Slice")'>Gel Slice</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Gel Slice")'>Gel Slice</a>



### Outputs


- **Fragment** [F]  
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
  true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# Purify Gel Protocol

# This protocol purfies gel slices into DNA fragment stocks.
needs "Standard Libs/Feedback"
class Protocol
  include Feedback
  # TODO refactor density parameter name? (see qg_volumes and iso_volumes definitions)
  DENSITY1 = 1.0 / 3000.0
  DENSITY2 = 1.0 / 1000.0
  
  def main
  
    if debug
       operations.shuffle! 
    end
  
    keep_gel_slices = operations.first.plan.get(:choice) == "Yes"
    
    operations.retrieve interactive: (!keep_gel_slices)
    operations.sort! { |op1, op2| op1.input("Gel").item.id <=> op2.input("Gel").item.id }
    operations.make
    
    # While testing, assign a random weight value
    operations.each{ |op| op.set_input_data("Gel", :weight, Random.rand / 2 + 0.1)  } if debug

    operations.each do |op|
        op.temporary[:qg_volume]  = (op.input_data("Gel", :weight).to_f / DENSITY1).floor
        op.temporary[:iso_volume] = (op.input_data("Gel", :weight).to_f / DENSITY2).floor
        op.temporary[:iso_volume] = 0 if op.input("Gel").sample.properties["Length"].between?(500, 4000)
        op.temporary[:total_volume] = op.temporary[:qg_volume] + op.temporary[:iso_volume]
        op.temporary[:is_divided] = op.temporary[:total_volume] >= 2000
    end
    
    move_gel_slices_to_tubes
    
    add_QG_buffer
    
    # Place tubes in a 50 degree heat block
    heat_block
    
    # Distribute melted gel slices between tubes
    distribute_gels
    
    # Add isopropanol
    add_isopropanol
    
    # Prepare the centrifuge
    prepare_centrifuge
    
    # Use the centrifuge to bind DNA to the columns
    centrifuge
    
    # Label the new 1.5 mL tubes
    use_label_printer
    
    # Transfer to the 1.5 ml tube
    transfer_to_tube
    
    #Measure the DNA concentration
    measure_DNA
    
    operations.each do |op|
      # need to check the case where its > 10
      #if operations.output_item("Fragment")
      op.set_output_data("Fragment", :concentration, op.temporary[:conc])
      op.output("Fragment").item.notes =  op.temporary[:note]
    end
    
    # table operations.start_table
    #   .output_item("Fragment")
    #   .get(:conc, type: 'number', heading: "Concentration (ng/uL)", default: 7)
    #   .get(:note, type: 'text', heading: "Notes")
    #   .end_table

    # Decide whether or not to keep the dilute stocks
    choices = get_choices

    discard_fragment_stocks choices
    
    # Let the tech select what concentrations were too low to continue, and mark the gels as deleted.
    select_as_deleted choices
    
    operations.store
    
    get_protocol_feedback
    return {}
    
  end
  
  # This method lets the technician decide whether or not to discard
  # any of the fragment stocks and returns their choices.
  def get_choices
    choices = show do
      title "Decide whether to keep dilute stocks"
      note "The below stocks have a concentration of less than 10 ng/uL."
      note "Talk to a lab manager to decide whether or not to discard the following stocks."
      operations.select{ |op| op.output_data("Fragment", :concentration) < 10}.each do |op|
        select ["Yes", "No"], var: "d#{op.output("Fragment").item.id}", label: "Discard Fragment Stock #{op.output("Fragment").item.id}", default: 1
      end
    end if operations.any?{ |op| op.output_data("Fragment", :concentration) < 10}
    choices #return
  end

  # This method tells the technician to move the gel slices to new tubes.
  def move_gel_slices_to_tubes
    show do
      title "Move gel slices to new tubes"
      note "Please carefully transfer the gel slices in the following tubes each to a new 2.0 mL tube using a pipette tip:"
      table operations.select{|op| op.temporary[:total_volume].between?(1500, 2000)}.start_table
      .input_item("Gel")
      .end_table
      note "Label the new tubes accordingly, and discard the old 1.5 mL tubes."
    end if operations.any? {|op| op.temporary[:total_volume].between?(1500, 2000)}
  end
  
  # This method displays a table of gels and tells the technician to add QG buffer
  # to the corresponding tubes.
  def add_QG_buffer
    show do
      title "Add the following volumes of QG buffer to the corresponding tube."
      table operations.start_table
      .input_item("Gel")
      .custom_column(heading: "QG Volume in uL", checkable: true) { |op| op.temporary[:qg_volume]}
      .end_table
    end
  end
  
  # This method tells the technician to place all tubes in a heat block.
  def heat_block
    show do
      title "Place all tubes in 50 degree heat block"
      timer initial: { hours: 0, minutes: 10, seconds: 0}
      note "Vortex every few minutes to speed up the process."
      note "Retrieve after 10 minutes or until the gel slice is competely dissovled."
    end
  end
  
  # This method tells the technician to distribute melted gel slices equally
  # between tubes. They then need to label the new tubes and discard the old tubes.
  def distribute_gels
    show do
      title "Equally distribute melted gel slices between tubes"
      note "Please equally distribute the volume of the following tubes each between two 1.5 mL tubes:"
      table operations.select{ |op| op.temporary[:is_divided]}.start_table
      .input_item("Gel")
      .end_table
      note "Label the new tubes accordingly, and discard the old 1.5 mL tubes."
    end if operations.any? { |op| op.temporary[:is_divided] }
  end
  
  # This method tells the technician to add isopropanol evenly between two tubes.
  def add_isopropanol
    show do
      title "Add isopropanol"
      note "Add isopropanol according to the following table. Pipette up and down to mix."
      warning "Divide the isopropanol volume evenly between two 1.5 mL tubes #{operations.select{ |op| op.temporary[:is_divided]}.map{ |op| op.input("Gel").item.id}} since you divided one tube's volume into two earlier." if operations.any?{ |op| op.temporary[:is_divided]}
      table operations.select{ |op| op.temporary[:iso_volume] > 0 }.start_table
      .input_item("Gel")
      .custom_column(heading: "Isopropanol (uL)", checkable: true) { |op| op.temporary[:iso_volume]}
      .end_table
    end if operations.any? { |op| op.temporary[:iso_volume] > 0}
  end
   
   # This method tells the technician to prepare the centrifuge.
   def prepare_centrifuge
    show do
      title "Prepare the centrifuge"
      check "Grab #{operations.length} pink Qiagen columns, label with 1 to #{operations.length} on the top."
      check "Add tube contents to LABELED pink Qiagen columns using the following table."
      check "Be sure not to add more than 750 uL to each pink column."
      warning "Vortex QG mixture thoroughly before adding to pink column!".upcase
      table operations.start_table
      .input_item("Gel")
      .custom_column(heading: "Qiagen column") { |op| operations.index(op) + 1}
      .end_table
    end
   end
  
   # This method gives instructions on how to operate the centrifuge.
   def centrifuge
    show do
      title "Centrifuge"
      check "Spin at 17.0 xg for 1 minute to bind DNA to columns"
      check "Empty collection columns by pouring liquid waste into liquid waste container."
      warning "Add the remaining QG mixtures to their corresponding columns, and repeat these first two steps for all tubes with remaining mixture!"
      check "Add 750 uL PE buffer to columns and wait five minutes"
      check "Spin at 17.0 xg for 30 seconds to wash columns."
      check "Empty collection tubes."
      check "Add 500 uL PE buffer to columns and wait five minutes"
      check "Spin at 17.0 xg for 30 seconds to wash columns"
      check "Empty collection tubes."
      check "Spin at 17.0 xg for 1 minute to remove all PE buffer from columns"
    end
    
   end    
   
   # This method tells the technician how to use the label printer.
   def use_label_printer
    show do
      title "Use label printer to label new 1.5 mL tubes"
      check "Ensure that the B33-143-492 labels are loaded in the printer. This number should be displayed on the printer. If not, check with a lab manager."
      check "Open the LabelMark 6 software."
      check "Select \"Open\" --> \"File\" --> \"Serialized data top labels\""
      note "If an error about the printer appears, press \"Okay\""
      check "Select the first label graphic, and click on the number in the middle of the label graphic."
      check "On the toolbar on the left, select \"Edit serialized data\""
      check "Enter #{operations.first.output("Fragment").item.id} for the Start number and #{operations.length} for the Total number, and select \"Finish\""
      check "Select \"File\" --> \"Print\" and select \"BBP33\" as the printer option."
      check "Press \"Print\" and collect the labels."
      image "purify_gel_edit_serialized_data"
      image "purify_gel_sequential"
    end       
   end
   
   # This method tells the technician to transfer pink columns to labeled tubes.
   def transfer_to_tube
    show do
        title "Transfer to 1.5 mL tube"
        check "Grab #{operations.length} 1.5 mL tube(s)."
        check "Apply the labels to the tubes."
        check "Transfer pink columns to the labeled tubes using the following table."
        table operations.start_table
            .custom_column(heading: "Qiagen column") { |op| operations.index(op) + 1 }
            .output_item("Fragment", heading: "1.5 mL tube", checkable: true)
        .end_table
        check "Add 30 uL molecular grade water or EB elution buffer to center of the column."
        warning "Be very careful to not pipette on the wall of the tube."
    end
   end
   
   # This method tells the technician to measure the DNA concentration.
   def measure_DNA
    show do
      title "Measure DNA Concentration"
      check "Elute DNA into 1.5 mL tubes by spinning at 17.0 xg for one minute, keep the columns."
      check "Pipette the flow through (30 uL) onto the center of the column, spin again at 17.0 xg for one minute. Discard the columns this time."
      # check "Go to B9 and nanodrop all of 1.5 mL tubes, enter DNA concentrations for all tubes in the following:"
      table operations.start_table
      .output_item("Fragment")
      .get(:conc, type: 'number', heading: "Concentration (ng/uL)", default: 7)
      .get(:note, type: 'text', heading: "Notes")
      .end_table
    end
   end
   
   # This method takes in a group of fragment stocks and tells the technician to discard
   # any of the fragment stocks that the technician earlier said that needed to be removed.
   def discard_fragment_stocks choices
     if !choices.nil? && choices.any? { |key, val| val == "Yes"}
      show do
        title "Discard fragment stocks"
        note "Discard the following fragment stocks:"
        note operations.select{ |op| choices["d#{op.output("Fragment").item.id}".to_sym] == "Yes"}
          .map{ |op| op.output("Fragment").item.id}
          .join(", ")
      end
     end
   end
   
   # This method takes in a group of fragment stocks and errors the operations
   # that include fragment stocks that have too low of concentrations.
   def select_as_deleted choices
     if !choices.nil?
      operations.select { |op| choices["d#{op.output("Fragment").item.id}".to_sym] == "Yes" }.each do |op|
          frag = op.output("Fragment").item
          op.error :low_concentration, "The concentration of #{frag} was too low to continue"
          frag.mark_as_deleted
      end
    end
    
    operations.each do |op|
      op.input("Gel").item.mark_as_deleted
    end
   end
end


```
