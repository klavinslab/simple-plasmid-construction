# Send to Sequencing

Sends sequencing primer and plasmid stock to Genewiz.

The technician will mix the sequencing primer and plasmid stock in a stripwell. They then fill
out the form on the Genewiz website and place the stripwell in the Genewiz dropbox.

Ran after **Make Miniprep** and is a precursor to **Upload Sequencing Results**.

### Inputs


- **Plasmid** [P]  
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Plasmid Stock")'>Plasmid Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Fragment Stock")'>Fragment Stock</a>
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Maxiprep Stock")'>Maxiprep Stock</a>

- **Sequencing Primer** [SP]  
  - <a href='#' onclick='easy_select("Sample Types", "Primer")'>Primer</a> / <a href='#' onclick='easy_select("Containers", "Primer Aliquot")'>Primer Aliquot</a>



### Outputs


- **Plasmid for Sequencing** [P]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Sequencing Stripwell")'>Sequencing Stripwell</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Sequencing Stripwell")'>Sequencing Stripwell</a>

### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
  true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

needs 'Cloning Libs/Cloning'
needs 'Standard Libs/Feedback'

class Protocol
  include Feedback
  include Cloning

  PLASMID = 'Plasmid'
  PRIMER = 'Sequencing Primer'
  SEQ_RESULT = 'Plasmid for Sequencing'
  GENEWIZ_USER = Parameter.get('Genewiz User')
  GENEWIZ_PASS = Parameter.get('Genewiz Password')

  def main
    operations.retrieve
    # Raise error if fragment length is invalid

    # Check for valid fragment lengths
    operations.each do |op|
      if op.input(PLASMID).item.sample.properties['Length'].nil?
        raise "This fragment's length is not valid."
      end
    end

    check_concentration operations, PLASMID

    # calculate required input volumes based on Genewiz guide, store in values of op.temporary[<input>_vol]
    calculate_volumes

    # volume check using the volumes calculated in the previously called 'calculate_volumes' method
    check_volumes [PLASMID], :stock_vol, :your_plasmid_sucks, check_contam: true
    check_volumes [PRIMER], :primer_vol, :make_aliquots_from_stock, check_contam: true

    if operations.running.empty?
      show do
        title "It's your lucky day!"

        note "There's no sequencing to do. :)"
      end
      operations.store
      return {}
    end

    operations.make
    operations.each do |op|
      raise 'At least one of the output collections could not be made successfully' if op.output(SEQ_RESULT).item.nil?
    end

    stripwells = operations.output_collections['Plasmid for Sequencing']

    # label sequencing stripwell(s)
    prepare_stripwells stripwells

    # load stripwells with molecular grade water
    load_water stripwells

    # load stripwells with stock
    load_stock stripwells

    # load stripwells with primer
    load_primer stripwells

    # delete stripwells
    stripwells.each(&:mark_as_deleted)

    operations.store

    # create Genewiz order
    genewiz = genewiz_order

    # store stripwells in dropbox
    store_stripwells

    # save order data in stripwells
    save_order_data genewiz

    operations.store(interactive: false)

    get_protocol_feedback
    {}
  end

  # This method calculates water volume, stock volume, and primer volume.
  def calculate_volumes
    ng_by_length_plas = [500.0, 800.0, 1000.0].zip [6000, 10_000]
    ng_by_length_frag = [10.0, 20.0, 40.0, 60.0, 80.0].zip [500, 1000, 2000, 4000]
    samples_list = []

    operations.each do |op|
      stock = op.input(PLASMID).item
      length = stock.sample.properties['Length']
      conc = stock.get(:concentration).to_f || rand(300) / 300
      conc = rand(4000..6000) / 10.0 if debug
      samples_list.push(op.input('Plasmid').sample)

      ng_by_length = stock.sample.sample_type.name == 'Plasmid' ? ng_by_length_plas : ng_by_length_frag
      plas_vol = ng_by_length.find { |ng_l| ng_l[1].nil? ? true : length < ng_l[1] }[0] / conc
      plas_vol = plas_vol < 0.5 ? 0.5 : plas_vol > 12.5 ? 12.5 : plas_vol

      water_vol_rounded = (((12.5 - plas_vol) / 0.2).floor * 0.2).round(1)
      plas_vol_rounded = ((plas_vol / 0.2).ceil * 0.2).round(1)
      primer_vol_rounded = 2.5

      op.temporary[:water_vol] = water_vol_rounded
      op.temporary[:stock_vol] = plas_vol_rounded
      op.temporary[:primer_vol] = primer_vol_rounded
    end
  end

  # This method tells the technician to prepare stripwells for the sequencing reaction.
  def prepare_stripwells(stripwells)
    show do
      title 'Prepare stripwells for sequencing reaction'

      stripwells.each_with_index do |_sw, idx|
        if idx < stripwells.length - 1
          check "Label the first well of an unused stripwell with UB#{idx * 12 + 1} and last
                 well with UB#{idx * 12 + 12}"
        else
          number_of_wells = operations.running.length - idx * 12
          check "Prepare a #{number_of_wells}-well stripwell, and label the first well with
                 UB#{idx * 12 + 1} and the last well with UB#{operations.running.length}"
        end
      end
    end
  end

  # This method tells the technician to load stripwells with molecular grade water.
  def load_water(stripwells)
    show do
      title "Load stripwells #{stripwells.map(&:id).join(', ')} with molecular grade water"

      stripwells.each_with_index do |sw, idx|
        note "Stripwell #{idx + 1}"
        table operations.running.select { |op| op.output('Plasmid for Sequencing').collection == sw }.start_table
                        .custom_column(heading: 'Well') { |op| op.output('Plasmid for Sequencing').column + 1 }
                        .custom_column(heading: 'Molecular Grade Water (uL)', checkable: true) { |op| op.temporary[:water_vol] }
                        .end_table
      end
    end
  end

  # This method tells the technician to load stripwells with plasmid stock.
  def load_stock(stripwells)
    show do
      title "Load stripwells #{stripwells.map(&:id).join(', ')} with plasmid stock"

      stripwells.each_with_index do |sw, idx|
        note "Stripwell #{idx + 1}"
        table operations.running.select { |op| op.output('Plasmid for Sequencing').collection == sw }.start_table
                        .custom_column(heading: 'Well') { |op| op.output('Plasmid for Sequencing').column + 1 }
                        .input_item(PLASMID, heading: 'Stock')
                        .custom_column(heading: 'Volume (uL)', checkable: true) { |op| op.temporary[:stock_vol] }
                        .end_table
      end
    end
  end

  # This method tells the technician to load stripwells with primer.
  def load_primer(stripwells)
    show do
      title "Load stripwells #{stripwells.map(&:id).join(', ')} with Primer"

      stripwells.each_with_index do |sw, idx|
        note "Stripwell #{idx + 1}"
        table operations.running.select { |op| op.output('Plasmid for Sequencing').collection == sw }.start_table
                        .custom_column(heading: 'Well') { |op| op.output('Plasmid for Sequencing').column + 1 }
                        .input_item(PRIMER, heading: 'Primer Aliquot')
                        .custom_column(heading: 'Volume (uL)', checkable: true) { |op| op.temporary[:primer_vol] }
                        .end_table
      end
    end
  end

  def valid?(tracking_number)
    tracking_number.present? && /\d{2}-\d+/.match(tracking_number)
  end

  # This method prompts the technician to go to the Genewiz wensite and create a new order.
  # This method returns the data captured by the show block that tells the technician
  # to create the Genewiz order.
  def genewiz_order
    operations.running.each do |op|
      stock = op.input(PLASMID).item
      primer = op.input(PRIMER).sample
      order_name_base = "#{stock.id}-#{stock.sample.user.name.gsub(/[^a-z]/i, '_')}"

      op.temporary[:seq_order_name_wo_primer] = order_name_base
      op.output(SEQ_RESULT).item.associate "seq_order_name_#{op.output(SEQ_RESULT).column}".to_sym, (order_name_base + "-#{primer.id}")
    end

    display_genewiz_instructions(operations)
    genewiz_tracking = get_genewiz_tracking_number

    genewiz_tracking
  end

  def display_genewiz_instructions(operations)
    show_return = show do
      title 'Create a Genewiz order'

      check "Go the <a href='https://clims3.genewiz.com/default.aspx' target='_blank'>GENEWIZ website</a>, log in with lab account (Username: #{GENEWIZ_USER}, password is #{GENEWIZ_PASS})."
      check "Click Create Sequencing Order, choose Same Day, Online Form, Pre-Mixed, #{operations.running.length} samples, then Create New Form"
      check 'Enter DNA Name and My Primer Name according to the following table, choose DNA Type to be Plasmid'

      table operations.start_table
                      .custom_column(heading: 'DNA Name') { |op| op.temporary[:seq_order_name_wo_primer] }
                      .custom_column(heading: 'DNA Type') { |op| op.input(PLASMID).sample.sample_type.name == 'Plasmid' ? 'Plasmid' : 'Purified PCR' }
                      .custom_column(heading: 'DNA Length') { |op| op.input(PLASMID).sample.properties['Length'] }
                      .custom_column(heading: 'My Primer Name') { |op| op.input(PRIMER).sample.id }
                      .end_table

      check 'Click Save & Review, Review the form and click Next Step'
      check 'Click Checkout'
      check 'Print out the form and enter the Genewiz tracking number on the next screen'
    end
  end

  def get_genewiz_tracking_number
    tracking_number = nil
    until valid?(tracking_number) || debug
      genewiz_tracking = show do
        if tracking_number.nil?
          title 'Enter the GeneWiz Tracking Number'
        else
          title 'Invalid GeneWiz Tracking Number. Try again.'
        end

        table operations.extend(OperationList).start_table
                        .custom_column(heading: 'Operation ID', &:id)
                        .custom_column(heading: 'Plan ID') { |op| op.plan.id }
                        .end_table

        get('text', var: 'tracking_num', label: 'Enter the Genewiz tracking number', default: 'TRACKING NUMBER')
        check 'Confirm that you properly entered the tracking number above'
      end
      tracking_number = genewiz_tracking[:tracking_num]
    end

    genewiz_tracking
  end

  # This method tells the technician to store the stripwells in the Genewiz dropbox.
  def store_stripwells
    show do
      title 'Put all stripwells in the Genewiz dropbox'
      check 'Cap all of the stripwells.'
      check 'Put the stripwells into a zip-lock bag along with the printed Genewiz order form.'
      check 'Ensure that the bag is sealed, and put it into the Genewiz dropbox.'
    end
  end

  # This method saves the order data of the genewiz order.
  def save_order_data(genewiz)
    order_date = Time.now.strftime('%-m/%-d/%y %I:%M:%S %p')
    operations.each do |op|
      op.set_output_data SEQ_RESULT, :tracking_num, genewiz[:tracking_num]
      op.set_output_data SEQ_RESULT, :order_date, order_date
    end
  end

  # This method takes inputs and tells the technician to discard any contaminated DNA stock items.
  def your_plasmid_sucks(bad_ops_by_item, _inputs)
    if bad_ops_by_item.keys.select { |item| item.get(:contaminated) == 'Yes' }.any?
      show do
        title 'discard contaminated DNA'

        note "discard the following contaminated DNA stock items: #{bad_ops_by_item.keys.select { |item| item.get(:contaminated) == 'Yes' }.map(&:id).to_sentence}"
      end
    end

    bad_ops_by_item.each do |item, _ops|
      bad_ops_by_item[item].each { |op| op.error :not_enough_volume, "Plasmid stock  #{item.id} did not have enough volume, or was contaminated. Please make another!" }
      bad_ops_by_item.except! item
      item.mark_as_deleted if item.get(:contaminated) == 'Yes'
    end
  end
end

```
