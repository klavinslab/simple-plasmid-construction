# frozen_string_literal: true

module Units
  # Volume
  MICROLITERS = 'µl'
  MILLILITERS = 'ml'

  # Weight
  NANOGRAMS = 'ng'

  # Concentration
  PICOMOLAR = 'pM'
  NANOMOLAR = 'nM'
  MICROMOLAR = 'µM'
  MILLIMOLAR = 'mM'
  MOLAR = 'M'

  # Temperature
  DEGREES_C = '°C'

  # Time
  MINUTES = 'min'
  SECONDS = 'sec'
  HOURS = 'hr'
  # Force
  TIMES_G = 'x g'

  # R/DNA Length
  BASEPAIRS = 'bp'
  KILOBASEPAIRS = 'kbp'
  MEGABASEPAIRS = 'mbp'
  GIGABASEPAIRS = 'gbp'

  # Voltage
  VOLTS = 'V'

  def self.qty_display(qty)
    "#{qty[:qty]} #{qty[:units]}"
  end

  def qty_display(qty)
    "#{qty[:qty]} #{qty[:units]}"
  end

  def add_qty_display(options)
    new_items = {}

    options.each do |key, value|
      key =~ /^(.+_)+([a-z]+)$/

      case Regexp.last_match(2)
      when 'microliters'
        units = MICROLITERS
      when 'milliliters'
        units = MILLILITERS
      when 'minutes'
        units = MINUTES
      else
        next
      end

      qty = value.to_f

      new_items["#{Regexp.last_match(1)}qty".to_sym] = {
        qty: qty, units: units
      }
    end

    options.update(new_items)
  end

  # Return the unit constant for the the unit name if there is one.
  #
  # @param unit_name [String] the name of the unit
  # @returns the value of the constant with the given name
  # @raises BadUnitNameError if the name is not the name of a defined unit
  def self.get_unit(unit_name:)
    const_get(unit_name.upcase)
  rescue StandardError
    raise BadUnitNameError.new(name: unit_name)
  end

  # Exception class for bad unit name arguments to Units::get_unit.
  #
  # @attr_reader [String] name  the bad unit name
  class BadUnitNameError < StandardError
    attr_reader :name

    def initialize(msg: 'Unknown unit name', name:)
      @name = name
      super(msg)
    end
  end

  # Return a key for the measure hash defined on the given object type.
  #
  # The measure hash must be defined in the data property of the object
  # type as JSON.
  # For instance
  #
  #   { "measure": { "type": "concentration", "unit": "micromolar" } }
  #
  # The key is constructed as the type name, an underscore, and the unit name.
  #
  #   "concentration_µM"
  #
  # @param object_type [ObjectType] the object type
  # @returns the key for the measure of the the object type if there is one
  # @raises MissingObjectTypeMeasure if the object type has no measure data_object
  def self.get_measure_key(object_type:)
    data_object = object_type.data_object
    raise MissingObjectTypeMeasureError.new(name: object_type.name) unless data_object.key?(:measure)

    measure = object_type.data_object[:measure]
    type_name = measure[:type]
    unit_name = measure[:unit]
    "#{type_name}_#{get_unit(unit_name: unit_name)}"
  end

  # Exception class for an object type without a measure hash definition.
  #
  # @attr_reader [String] name  the name of the object type
  class MissingObjectTypeMeasureError < StandardError
    attr_reader :name

    def initialize(msg: 'ObjectType has no measure in data object', name:)
      @name = name
      super(msg)
    end
  end
end
