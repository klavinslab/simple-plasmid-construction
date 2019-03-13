# Upload Sequencing Results

Uploads sequencing results.

The technician uploads the sequencing results, and the user is prompted to verify whether the sequence is correct. If the sequence is correct, the overnight that holds the plasmid cells is automatically submitted to **Make Glycerol Stock**; if the results are incorrect, the plate and overnight associated with the plasmid stock are thrown out. 

Run after **Send to Sequencing** and is a precursor to **Make Glycerol Stock**. 
### Inputs


- **Plasmid** [P]  Part of collection
  - <a href='#' onclick='easy_select("Sample Types", "Plasmid")'>Plasmid</a> / <a href='#' onclick='easy_select("Containers", "Sequencing Stripwell")'>Sequencing Stripwell</a>
  - <a href='#' onclick='easy_select("Sample Types", "Fragment")'>Fragment</a> / <a href='#' onclick='easy_select("Containers", "Sequencing Stripwell")'>Sequencing Stripwell</a>





### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(op)
  if op.input("Plasmid").item
      order_name = op.input("Plasmid").item.get "seq_order_name_#{op.input("Plasmid").column}".to_sym
      
      # associate old sequencing name style (just in case)
      if order_name.nil?
        op.input("Plasmid").item.associate "seq_order_name_#{op.input("Plasmid").column}".to_sym, "#{op.input("Plasmid").item.id}_#{op.input("Plasmid").column}"
    end
  end
  
  true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

# Creates "Clean Up Sequencing" operation only if plate matches the allowable_field_types found in "Clean Up Sequencing" Plate input   Aug 17, 2018 JV

needs 'Standard Libs/Debug'
needs 'Standard Libs/Feedback'

class Protocol
  include Feedback
  include Debug

  ORDER = 'Plasmid'
  GENEWIZ_USER = Parameter.get('Genewiz User')
  GENEWIZ_PASS = Parameter.get('Genewiz Password')
  AQ_URL = Parameter.get('URL')

  def main
    add_debug_defaults

    # TODO: manage batches of operations by tracking number
    tracking_num = ensure_valid_tracking_number
    return {} if tracking_num.blank?

    operations.retrieve interactive: false

    return {} unless results_have_arrived?(tracking_num)
    upload_batched_results tracking_num
    upload_individual_results tracking_num

    operations.each do |op|
      # Query user for next step
      op.plan.associate "Item #{op.temporary[:seq_name].split('-')[0]} sequencing ok?", 'yes - discard plate, and mark plasmid stock as sequence verified; resequence - keep plate and plasmid stock; no - discard plasmid stock'
    end
    add_clean_up_sequencings(operations.running)
    notify_users

    get_protocol_feedback

    {}
  end

  # This method sets variables to a default value during debug mode.
  def add_debug_defaults
    if debug
      operations.each do |op|
        sw = op.input(ORDER).item
        sw.associate :tracking_num, [12_345, 23_523].sample unless sw.get(:tracking_num)

        key = "seq_order_name_#{op.input(ORDER).column}"
        next unless sw.associations.none? { |k, _v| k == key }
        stock = Item.where(object_type_id: ObjectType.find_by_name('Plasmid Stock')).all.sample
        primer = Item.where(object_type_id: ObjectType.find_by_name('Primer Stock')).all.sample.sample

        sw.associate key.to_sym, "#{stock.id}-#{stock.sample.user.name}-#{primer.id}"
      end
    end
  end

  def valid?(tracking_number)
    tracking_number.present? and /\d{2}-\d+/.match(tracking_number)
  end

  # This method ensures that all the operations involved have the same
  # tracking number.
  def ensure_valid_tracking_number
    ops_by_num = Hash.new { |h, k| h[k] = [] }
    operations.each { |op| ops_by_num[op.input(ORDER).item.get(:tracking_num)].push op }
    tracking_numbers = ops_by_num.keys

    tracking_number =
      if tracking_numbers.include?(nil)
        get_missing_tracking_number(ops_by_num[nil])
      elsif tracking_numbers.length == 1
        tracking_numbers.first
      else
        handle_multiple_tracking_numbers(op_map: ops_by_num)
      end

    unless valid?(tracking_number)
      # TODO: check for invalid IDs
      show do
        title 'Tracking number is not valid'

        note 'Setting operations to pending'
      end
      operations.each { |op| op.change_status 'pending' }
    end

    tracking_number
  end

  # Collects operations that have a blanck tracking number and asks for the
  # tracking number to be added. Returns the entered tracking number.
  #
  def get_missing_tracking_number(operations)
    # TODO: change so that can handle multiple batches with different tracking numbers
    genewiz_tracking = show do
      title 'The following operations have no tracking number'

      table operations.extend(OperationList).start_table
                      .custom_column(heading: 'Operation ID', &:id)
                      .custom_column(heading: 'Plan ID') { |op| op.plan.id }
                      .end_table

      get('text', var: 'tracking_num', label: 'Enter the Genewiz tracking number', default: 'TRACKING NUMBER')
      check 'Confirm that you properly entered the tracking number above'
    end

    # TODO: deal with bad tracking number
    tracking_number = genewiz_tracking[:tracking_num]

    # code from send to sequencing
    operations.each do |op|
      # TODO: change this to operate directly on item instead of using method
      op.set_input_data(ORDER, :tracking_num, tracking_number)
    end

    tracking_number
  end

  def handle_multiple_tracking_numbers(op_map:)
    show do
      title 'Error: there are multiple tracking numbers'

      note "There are #{op_map.keys.length} different tracking numbers"
      note 'Please consider the suggested batching option.'

      op_map.each do |num, ops|
        if num.present?
          note "Tracking number: #{num}"
        else
          note 'No tracking number:'
        end

        table ops.extend(OperationList).start_table
                 .custom_column(heading: 'Operation ID', &:id)
                 .custom_column(heading: 'Plan ID') { |op| op.plan.id }
                 .end_table
      end
    end

    nil
  end

  # This method asks the technician to see if the sequencing results have arrived.
  def results_have_arrived?(tracking_num)
    results_info = show do
      title 'Check if Sequencing results arrived?'

      check "Go the Genewiz website, log in with lab account (Username: #{GENEWIZ_USER}, password is #{GENEWIZ_PASS})."
      note "In Recent Results table, click Tracking Number #{tracking_num}, and check if the sequencing results have shown up yet."

      select %w[Yes No], var: 'results_back_or_not', label: 'Do the sequencing results show up?', default: 0
    end

    if results_info[:results_back_or_not] == 'No'
      show do
        title 'No Results'
        note 'Sequencing results are not yet available, wait a while and then run this job again.'
      end
      operations.each do |op|
        op.change_status 'pending'
      end
      return false
    end

    true
  end

  # USERS DO NOT NEED FULL BATCH OF SEQUENCING RESULTS, THEY ONLY WANT THEIR OWN RESULTS ASSOCIATED WITH THEIR PLAN
  def upload_batched_results(tracking_num)
    show do
      title 'Download Genewiz Sequencing Results zip file'

      note "Click the button 'Download All Selected Trace Files' (Not Download All Sequence Files), which should download a zip file named #{tracking_num}-some-random-number.zip."
      #   note "Upload the #{tracking_num}_ab1.zip file here."

      #   upload var: "sequencing_results"
    end

    # uploads = sequencing_uploads_zip[:sequencing_results]
    # if uploads
    #   u = Upload.find(uploads.first[:id])
    #   operations.each do |op|
    #       op.plan.associate "Order #{tracking_num} batched sequencing results", "Fresh out of the oven!", u
    #       op.input("Plasmid").item.associate "Order #{tracking_num} batched sequencing results", "Fresh out of the oven!", u
    #   end
    # end
  end

  # This method tells the technician to upload individual sequencing results
  #
  # @param tracking_num [Integer] the tracking number of results
  def upload_individual_results(tracking_num)
    operations.each { |op| op.temporary[:upload_confirmed] = false }

    5.times do
      ops = operations.reject { |op| op.temporary[:upload_confirmed] }
      break if ops.empty?
      ops.each { |op| op.temporary[:seq_name] = op.input(ORDER).item.get "seq_order_name_#{op.input(ORDER).column}".to_sym }

      sequencing_uploads = show do
        title 'Upload individual sequencing results'

        note "Unzip the downloaded zip file named #{tracking_num}_ab1.zip."
        note "If you are on a Windows machine, right click the #{tracking_num}-some-random-number.zip file, click Extract All, then click Extract."
        note 'Upload all the unzipped ab1 file below by navigating to the upzipped folder.'
        note 'You can click Command + A on Mac or Ctrl + A on Windows to select all files.'
        note 'Wait until all the uploads finished (a number appears at the end of file name).'

        upload var: 'sequencing_results'

        table ops.start_table
                 .custom_column(heading: 'Expected Filenames') { |op| op.temporary[:seq_name] + '.ab1' }
                 .end_table
      end

      # TODO: remove hacky way and replace with correct way
      op_to_file_hash = match_upload_to_operations ops, :seq_name, job_id = jid
      op_to_file_hash.each do |op, u|
        op.plan.associate "#{op.input(ORDER).sample.name} in Item #{op.temporary[:seq_name]} sequencing results", 'How do they look?', u
        stock = Item.find(op.temporary[:seq_name].split('-')[0].to_i)
        stock.associate "Item #{op.temporary[:seq_name]} sequencing results", 'How do they look?', u
        if stock.get(:from)
          overnight = nil
          if Item.exists?(stock.get(:from).to_i)
            overnight = Item.find(stock.get(:from).to_i)
          else
            op.associate("Couldn't find the overnight, but thats okay!", '') # they might have sequenced without an overnight
          end
          if overnight&.get(:from)
            overnight.associate "Item #{op.temporary[:seq_name]} sequencing results", 'How do they look?', u
            gs = Item.find(overnight.get(:from))
            gs.associate "Item #{op.temporary[:seq_name]} sequencing results", 'How do they look?', u if gs.object_type.name.include? 'Glycerol Stock'
          end
        end

        op.temporary[:upload_confirmed] = u.present?
      end
    end
  end

  # method that matches uploads to operations with a temporary[filename_key]
  def match_upload_to_operations(ops, filename_key, job_id = nil, uploads = nil)
    def extract_basename(filename)
      ext = File.extname(filename)
      basename = File.basename(filename, ext)
    end

    op_to_upload_hash = {}
    uploads ||= Upload.where('job_id' => job_id).to_a if job_id
    if uploads
      ops.each do |op|
        upload = uploads.select do |u|
          basename = extract_basename(u[:upload_file_name])
          basename.strip.include? op.temporary[filename_key].strip
        end.first || nil
        op_to_upload_hash[op] = upload
      end
    end
    op_to_upload_hash
  end

  def add_clean_up_sequencings(ops)
    ops.each do |op|
      add_clean_up_sequencing(op)
    end
  end

  def add_clean_up_sequencing(op)
    if op.plan
      stock = Item.find(op.temporary[:seq_name].split('-')[0].to_i)
      #   show do
      #       title "stock :from"
      #       note "#{stock.get(:from).blank?}"
      #   end
      plate = nil
      unless stock.get(:from).blank?
        overnight = nil
        if Item.exists?(stock.get(:from).to_i)
          overnight = Item.find(stock.get(:from).to_i)
        else
          op.associate("Couldn't find the overnight, but thats okay!", '') # they might have sequenced without an overnight
        end
        # find items that match the afts of Clean Up Sequencing if they exist
        if overnight && !overnight.get(:from).blank?
          origin_item = Item.find(overnight.get(:from))
          clean_up_op = OperationType.find_by_name('Clean Up Sequencing')
          plate_ft = clean_up_op.field_types.find { |ft| ft.name == 'Plate' }
          plate_ft.allowable_field_types.each do |aft|
            if aft.sample_type_id == overnight.sample.sample_type.id && \
               aft.object_type_id == origin_item.object_type.id
              plate = origin_item
            end
          end
        end
      end

      return if plate.blank?

      # return nothing if no item was found
      # Ensure no Clean Up Sequencing operation exists for this plasmid stock
      cus_ops = op.plan.operations.select { |op| op.name == 'Clean Up Sequencing' }
      if cus_ops.map { |op| op.input('Stock').item }.exclude?(stock)
        # Make new Clean Up Sequencing for this stock and associated plate
        ot = OperationType.find_by_name('Clean Up Sequencing')
        new_op = ot.operations.create(
          status: 'waiting',
          user_id: op.user_id
        )
        op.plan.plan_associations.create operation_id: new_op.id

        aft = ot.field_types.find { |ft| ft.name == 'Stock' }.allowable_field_types[0]
        new_op.set_property 'Stock', stock.sample, 'input', false, aft
        new_op.input('Stock').set item: stock

        aft = ot.field_types.find { |ft| ft.name == 'Plate' }.allowable_field_types[0]
        new_op.set_property 'Plate', stock.sample, 'input', false, aft
        new_op.input('Plate').set item: plate

        op.plan.reload
        new_op.reload
      end
    end
  end

  # This method notifies users that the sequencing results are ready.
  def notify_users
    user_to_op = Hash.new { |_hash, key| user_to_op[key] = [] }
    operations.each do |op|
      user_to_op[op.user].push(op)
    end

    user_to_op.each do |user, oplist|
      plans = oplist.map(&:plan).uniq
      subject = 'Sequencing Results Ready'
      message = "<p>Hello #{user.name},<br>You have sequencing results ready in Aquarium. Please check your results, and be sure to mark whether your items are verified or not on the planner page in order for your #{'plan'.pluralize(plans.length)} to move along."
      plans.each do |plan|
        message += "<br><a href='#{AQ_URL}/launcher?plan_id=#{plan.id}'>#{plan.id} - #{plan.name}</a>"
      end
      message += '</p> <p>Thanks!<br> </p> <p>This is an automated message</p>'

      user.send_email subject, message unless debug
    end
  end
end

```
