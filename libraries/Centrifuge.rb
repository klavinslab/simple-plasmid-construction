# abemill@uw.edu
# This module is made to cover all common cases of directing the tech to
# centrifuge, decant, and resuspend multiple batches of tubes.
# centrifuge_resuspend_cycle is the public method of this module.
# It allows staggered centrifuging so that the tech can be resuspending
# the previous batch while the next batch is centrifuging.
module Centrifuge
  class Batch
    attr_reader :marker, :tubes

    def initialize(args)
      @marker = args[:marker]
      @tubes = args[:tubes]
    end

    # Partition the given tubes list into batches.
    # Returns a list of Batch objects, each having a letter marker, and a list
    # of tubes.
    def self.initialize_batches(tubes, centrifuge_slots, protocol)
      @@protocol = protocol # we need this to use show commands in Batch methods
      @@batch_size = centrifuge_slots
      tube_batches = tubes.each_slice(centrifuge_slots).to_a
      batches = []
      tube_batches.each_with_index do |tube_batch, i|
        batch_id = [(i + 65).chr]
        batches.push Batch.new(marker: batch_id, tubes: tube_batch)
      end
      batches
    end
    
    def self.batch_size
      @@batch_size
    end

    # returns a new list of batches produced by reducing the amount of tubes in
    # each batch and then combining batches, Batches.size will be halved.
    def self.combine_batches(batches)
      paired_batches = batches.each_slice(2).to_a
      batches = []
      paired_batches.each do |pair|
        pair.each_with_index do |batch, i|
          pair[i] = batch.combine_tubes
        end
        batches.push(pair[0].combine_with(pair[1]))
      end
      batches
    end

    # Instructs tech to reduce the number of tubes in the given batch by a power
    # of 2, combining tubes of the same sample. This only shows the instructions
    # and does not alter the state of batches[].
    # (that happens in combine_batches)
    def combine_tubes_instructions()
      batch = self
      @@protocol.show do
        title 'Combine Tubes'
        if batch.marker.length == 1
          note 'Reduce the number of tubes in '\
               "<b>batch #{batch.marker.to_sentence}</b> from #{batch.tubes.length} "\
               "to #{batch.tubes.length / 2} by combining tubes."
        else
          note "Together, <b>batches #{batch.marker.to_sentence}</b> have a "\
               "total of #{batch.tubes.length} tubes. Reduce the sum of tubes to "\
               "#{batch.tubes.length / 2} by combining tubes from "\
               "#{batch.marker.length == 2 ? 'both' : 'all'} batches."
        end
        note 'Combine tubes by carefully pouring one tube into tube '\
             'that shares the same id.'
        note 'All tubes after combination should have the same volume. '\
             'Do not "double combine" any tubes.'
        batch.tubes.uniq.each do |tube|
          note "Combine each tube labeled <b>#{tube}</b> "\
               "with another tube labeled <b>#{tube}</b>."
        end
        if Cycle.cold?
          warning 'Once finished with combining, '\
                  'immediately place tubes in ice bath.'
        end
      end
    end

    # instructions to place tubes from batch into the centrifuge
    def centrifuge(centrifuge_instructions)
      rpm = centrifuge_instructions[:rpm]
      time = centrifuge_instructions[:time]
      temp = centrifuge_instructions[:temp]
      batch = self
      @@protocol.show do
        title 'centrifuge tubes'
        note "Set the centrifuge to #{rpm} rpm for #{time} minutes at "\
             "#{temp} C. Ensure correct centrifuge tube holders are in place."
        note "Move all tubes from <b>#{'batch'.pluralize(batch.marker.length)} "\
             "#{batch.marker.to_sentence}</b> to centrifuge and press start."
        if batch.tubes.length.odd?
          warning 'Balance the centrifuge with a dummy tube that is filled '\
                  'with the same volume of liquid as the other tubes.'
        end
      end
    end

    # instructions to remove tubes from the centrifuge
    # after it has finished a spin
    def remove_tubes()
      batch = self
      @@protocol.show do
        title 'Remove Tubes from Centrifuge'
        note 'Wait for centrifuge to finish'
        note 'Once the centrifuge has finished its spin, '\
             'remove tubes from centrifuge.'
        note "The removed tubes should be marked as "\
             "<b>#{'batch'.pluralize(batch.marker.length)} "\
             "#{batch.marker.to_sentence}</b>."
        if Cycle.cold?
          warning 'Once removed from centrifuge, '\
                'immediately place tubes in ice bath.'
        end
      end
    end

    # instructions to resuspend tubes
    def resuspend(resuspend_instructions)
      volume = resuspend_instructions[:volume]
      media = resuspend_instructions[:media]

      decant()

      batch = self
      @@protocol.show do
        title "Resuspend cells in #{volume}mL of #{media}"
        note "Grab bottle of #{media} from fridge."
        note "Carefully pour #{volume}mL of #{media} into each tube from <b>"\
             "#{'batch'.pluralize(batch.marker.length)} #{batch.marker.to_sentence}</b>."
        note 'Shake and vortex tubes until pellet is completely resuspended.'
        warning 'When not actively shaking or vortexing keep tubes in ice, '\
                'and place all tubes in ice once resuspended.' if Cycle.cold?
        note "At next opportunity, bring #{media} back to fridge, "\
             'or to dishwasher if empty.'
      end
    end

    def decant()
      batch = self
      @@protocol.show do
        title 'Decant tubes'
        note "Take #{Cycle.cold? ? 'ice bucket' : 'tubes'} to the "\
             "dishwasing station, and pour out supernatant of tubes from <b>"\
             "#{'batch'.pluralize(batch.marker.length)} #{batch.marker.to_sentence}</b>."
        note 'Place tubes in ice immediately after decanting.' if Cycle.cold?
      end
    end

    # returns new batch which is the combination of this batch
    # and the other batch
    # helper for combine_batches
    def combine_with(other)
      if other
        new_marker = marker.concat other.marker
        new_tubes = tubes.concat other.tubes
        return Batch.new(marker: new_marker, tubes: new_tubes)
      else
        return self
      end
    end

    # returns a new batch with a half the tubes, where like tubes have been
    # combined.
    # helper for combine_batches
    def combine_tubes
      new_tubes = []
      new_tubes.concat(tubes)
      batch = Batch.new(marker: marker,tubes: [])
      tubes.uniq.each do |short_id|
        sameids = new_tubes.select { |tube| tube == short_id }
        batch.tubes.concat(sameids[0, sameids.length / 2])
      end
      batch
    end
  end

  class Cycle
    attr_reader :centrifuge_instructions, :resuspend_instructions
    def initialize(cycle_instructions)
      @centrifuge_instructions = { temp: cycle_instructions[:cent_temp],
                                   rpm: cycle_instructions[:cent_rpm],
                                   time: cycle_instructions[:cent_time] }

      @resuspend_instructions = { media: cycle_instructions[:sus_media],
                                  volume: cycle_instructions[:sus_volume] }

      @combine = cycle_instructions[:combine]
    end

    def self.initialize_cycles(cycles_data, cold)
      @@cold = cold
      cycles = cycles_data.map do |cycle_data|
        Cycle.new(cycle_data)
      end
      cycles
    end

    def self.cold?
      @@cold
    end

    def combine?
      @combine
    end
  end

  ##
  # @param [Hash] opts  The parameters which indicate cycling behaivor
  # @option [Array<Item>] items  The array of items for which each will
  #           be split into smaller tubes and then centrifuge cycled on.
  # @option [Float] start_vol  Volume of liquid that each item begins with.
  # @option [Float] tube_vol  Volume of centrifuge tubes that
  #           start_vol will be divided amongst
  # @option [Integer] centrifuge_slots  Number of slots in the centrifuge.
  #           Must be an even number.
  # @option [Array<Hash>] cycles  Instructions for each cycle of centrifuging.
  #           Cycles.length indicates how many centrifuge/wash cycles.
  #           Elements of cycles contain instructions for the centrifuging
  #           and resuspension settings for that cycle.
  # @option [Boolean] :cold  Indicate if centrifuge cycling is done on ice.
  #           Default: no
  # @option [Symbol] :cb_extra_instructions  Extra instructions for tech
  #           while waiting for final centrifuge batch to finish,
  #           for example, tidying up workspace. Default: none
  # @effects  This method Instructs tech to do cycles of centrifuging,
  #           decanting, and resuspending on each item
  #           as per the instructions stored in cycles.
  def centrifuge_resuspend_cycle(opts = {})
    # Bench setup is required before we begin centrifuging
    # During setup, the items will be aliquoted into tubes,
    # and each aliquoted tube will be marked with a short id.
    # This maps tubes to the item they originated from, and will
    # keep track of which tubes contain the same substance.
    # the index of the parent item in the items[] is used
    # for the short id.
    # Also, tubes are grouped into batches that will fit in centrifuge,
    # and marked with a capital letter batch identifier, in addition to their
    # short id that indicates their ancestry.

    # computation
    tubes = initialize_tubes(opts)
    batches = Batch.initialize_batches(tubes, opts[:centrifuge_slots], self)
    cycles = Cycle.initialize_cycles(opts[:cycles], opts[:cold])

    # tech instructions
    setup_steps(cycles, batches,
              opts[:start_vol], opts[:tube_vol], opts[:items])

    # Loop through each cycle of centrifuging and resuspending found in cycles[]
    # and perform that cycle on each batch of tubes in found in batches[]
    this_batch = nil
    cycles.each_with_index do |cycle, i|
      prev_cycle = cycles[i - 1]
      
      # Reconfigure batches array to be shortened by combing batches
      # so each batch has enough tubes to fill centrifuge.
      batches = Batch.combine_batches(batches) if prev_cycle.combine?

      batch_iterator = batches.each
      first_batch = batch_iterator.next
      if i.zero?
        # first batch of first cycle, the centrifuge is empty
        first_batch.centrifuge(cycle.centrifuge_instructions)
      else
        this_batch.remove_tubes
        if batches.length == 1
          # this_batch == first_batch || first_batch contains this_batch
          this_batch.resuspend(prev_cycle.resuspend_instructions)
          this_batch.combine_tubes_instructions if prev_cycle.combine?
          first_batch.centrifuge(cycle.centrifuge_instructions)
        else
          # first_batch and this_batch are not associated,
          # we can start centrifuging first_batch before we resuspend this_batch
          first_batch.centrifuge(cycle.centrifuge_instructions)
          this_batch.resuspend(prev_cycle.resuspend_instructions)
          this_batch.combine_tubes_instructions if prev_cycle.combine?
        end
      end

      this_batch = first_batch
      while has_next? batch_iterator
        next_batch = batch_iterator.next
        this_batch.remove_tubes
        next_batch.centrifuge(cycle.centrifuge_instructions)
        this_batch.resuspend(cycle.resuspend_instructions)
        this_batch.combine_tubes_instructions if cycle.combine?
        this_batch = next_batch
      end
    end

    # Show any extra steps specified by client to do
    # while waiting for last spin to finish.
    extra_instructions(opts[:cb_extra_instructions])

    final_cycle = cycles.last
    this_batch.remove_tubes
    this_batch.resuspend(final_cycle.resuspend_instructions)
    if final_cycle.combine?
      this_batch.combine_tubes_instructions
      batches = Batch.combine_batches(batches)
    end

    # On remaining tubes,
    # replaces the short id with the id of original parent item.
    relabel_tubes(batches, opts[:items])
  end

  private

  # Ensures state of variables is acceptable
  # TODO add more checks
  def error_checks(cycles, batches, opts)
    raise 'odd slot centrifuge not supported' if Batch.batch_size.odd?
    raise 'wrong cycle amount' if cycles.length != opts[:cycles].length
    raise 'wrong batch size' if Batch.batch_size != opts[:centrifuge_slots]
  end

  # Initializes array of integers that represent tubes
  # identified by their short_id which corresponds to the parent item.
  # Also returns
  def initialize_tubes(opts)
    combination_occurs = opts[:cycles].any? { |cycle| cycle[:combine] == true }
    tubes_per_item = (opts[:start_vol] / opts[:tube_vol]).floor
    tubes_per_item += 1 if tubes_per_item.odd? && combination_occurs
    tubes = []
    opts[:items].each_with_index do |_item, i|
      tubes_per_item.times do
        tubes.push (i + 1)
      end
    end
    tubes
  end

  # Gives the tech instructions to prepare for centrifuging.
  def setup_steps(cycles, batches, start_vol, tube_vol, items)
    tubes = batches.map { |batch| batch.tubes }.flatten

    fetch_supplies(cycles, tubes.length, tube_vol)
    if Cycle.cold?
      prepare_ice_bath
      chill_tubes(tubes.length, tube_vol)
    end
    aliquot_items_to_tubes(items, tubes, start_vol, tube_vol)
    batch_tubes_instructions(batches)
  end

  # Instructs tech to fetch all the media and tubes that will be required.
  def fetch_supplies(cycles, num_tubes, tube_vol)
    media_to_volume = calculate_media_volumes(cycles, num_tubes)

    media_location = 'on bench'
    tube_location = 'on bench'
    if Cycle.cold?
      media_location = 'in fridge'
      tube_location = 'in freezer'
    end

    show do
      title 'Grab required suspension media'
      note 'For the following set of centrifuging instructions, you will need'\
           ' the following supplies: '
      media_to_volume.each do |media, volume|
        check "At least #{volume}mL of #{media}"
      end
      note "Place all media bottles #{media_location}"\
           ' in preparation for centrifuge.'
      note "Place #{num_tubes} #{tube_vol}mL tubes #{tube_location}"\
           ' in preparation for centrifuge.'
    end
  end

  def calculate_media_volumes(cycles, num_tubes)
    media_to_volume = Hash.new
    media_list = cycles.map do |cycle|
      cycle.resuspend_instructions[:media]
    end.uniq

    media_list.each do |media|
      volumes = cycles.select { |cycle|
        cycle.resuspend_instructions[:media] == media
      }.map { |cycle|
        cycle.resuspend_instructions[:volume]
      }
      total_volume = volumes.sum * num_tubes
      media_to_volume[media] = total_volume
    end
    media_to_volume
  end

  # Instructs tech to make an ice bath and immerse empty tubes in it.
  def prepare_ice_bath
    show do
      title 'Go to Bagley to get ice (Skip if you already have ice)'
      note 'Walk to ice machine room on the second floor in Bagley with a '\
           'large red bucket, fill the bucket  full with ice.'
      note 'If unable to go to Bagley, use ice cubes to make a water bath (of '\
           'mostly ice) or use the chilled aluminum bead bucket. (if using '\
           'aluminum bead bucket place it back in freezer between spins)'
    end
  end

  def chill_tubes(num_tubes, tube_vol)
    show do
      title 'Prepare chilled tubes'
      note "Take the #{num_tubes} #{tube_vol}mL "\
            "#{'tube'.pluralize(num_tubes)} from the freezer "\
            'and immerse in ice bath.'
    end
  end

  # Instructs the tech to divide the volume of each item in items[] into
  # equivolume aliquots for centrifuging.
  def aliquot_items_to_tubes(items, tubes, start_vol, tube_vol)
    tubes_per_item = tubes.length / items.length
    aliquot_amount = [start_vol / tubes_per_item, tube_vol].min

    show do
      title "Aliquot items into #{tube_vol}mL tubes for centrifuging"
      note 'You should have '\
           "#{items.length * tubes_per_item} #{tube_vol}mL tubes."
      if Cycle.cold?
        note 'While labeling and pouring, '\
             'leave tubes in ice bath as much as possible.'
      end
      items.each_with_index do |item, i|
        note "Label #{tubes_per_item} tubes with short id: <b>#{i + 1}</b>"
        note "Carefully pour #{aliquot_amount}mL from #{item} "\
             "into each tube labeled as <b>#{i + 1}</b>."
      end
      
      if Cycle.cold?
        note 'Leave tubes to chill for for 30 minutes.'
        timer initial: { hours: 0, minutes: 30, seconds: 0}
      end
    end
  end
  
  # Instructs the tech to group tubes into batches
  # that will fit into the centrifuge
  def batch_tubes_instructions(batches)
    show do
      title "separate tubes into batches of #{Batch.batch_size} or less"
      note 'Group tubes into batches as shown and mark each tube '\
           'with its alphabetic batch identifier.'
      batches.each do |batch|
        check "<b>#{batch.tubes.to_sentence}</b>: "\
              "batch <b>#{batch.marker}</b>"
      end
    end
  end
  
  # Callback which runs client specified method during the time when
  # the tech is waiting for the last batch of tubes to finish centrifuging.
  def extra_instructions(method_name)
    method(method_name.to_sym).call if method_name && (method_name != '')
  end

  # After centrifuging finishes, instruct tech to relabel the resulting tubes
  # with the id of the item that they originated from, for convienence.
  def relabel_tubes(batches, items)
    result_tubes = batches.map { |batch| batch.tubes }.flatten
    show do
      title 'Label Finished Tubes'
      note 'Tubes with the following ids remain: '\
           "<b>#{result_tubes.to_sentence}</b>."
      note 'Label each tube with the item id '\
           'of the item that they originated from.'
      items.each_with_index do |item, i|
        note "The tube(s) labeled as <b>#{i + 1}</b> "\
             "should be relabeled as <b>#{item.id}</b>."
      end
    end
  end

  # Helper method that allows manual iteration like in java
  # when used alongside enumerator.next()
  def has_next?(enum)
    enum.peek
    return true
  rescue StopIteration
    return false
  end
end
