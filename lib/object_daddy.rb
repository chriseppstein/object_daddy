module ObjectDaddy

  def self.included(klass)
    klass.extend ClassMethods
    if defined? ActiveRecord and klass < ActiveRecord::Base
      klass.extend RailsClassMethods    
      
      class << klass
        alias_method :validates_presence_of_without_object_daddy, :validates_presence_of
        alias_method :validates_presence_of, :validates_presence_of_with_object_daddy
      end   
    end
  end
    
  module ClassMethods
    attr_accessor :exemplars_generated, :exemplar_path, :generators, :generation_strategies
    attr_reader :presence_validated_attributes
    protected :exemplars_generated=
    
    # create a valid instance of this class, using any known generators
    def spawn(*args)
      strategy = unless args.first.is_a? Hash
        args.shift
      end
      args = args.shift || {}
      gather_exemplars
      (generators_for(strategy) || {}).each_pair do |handle, gen_data|
        next if args[handle]
        generator = gen_data[:generator]
        if generator[:block]
          if generator[:start]
            generator[:prev] = args[handle] = generator[:start]
            generator.delete(:start)
          else
            generator[:prev] = args[handle] = generator[:block].call(generator[:prev])
          end
        elsif generator[:method]
          args[handle] = send(generator[:method])
        elsif generator[:class] || generator[:object]
          args[handle] = (generator[:class] || generator[:object]).next
        end
      end
      if presence_validated_attributes and !presence_validated_attributes.empty?
        req = {}
        (presence_validated_attributes.keys - args.keys).each {|a| req[a.to_s] = true } # find attributes required by validates_presence_of not already set
        
        belongs_to_associations = reflect_on_all_associations(:belongs_to).to_a
        missing = belongs_to_associations.select { |a|  req[a.name.to_s] or req[a.primary_key_name.to_s] }
        if create_scope = scope(:create)
          missing.reject! { |a|   create_scope.include?(a.primary_key_name) }
        end
        missing.each {|a| args[a.name] = a.class_name.constantize.generate }
      end
      returning(new) do |record|
        args.each do |k, v|
          record.send("#{k}=", v)
        end
      end
    end

    # register a generator for an attribute of this class
    # generator_for :foo do |prev| ... end
    # generator_for :foo do ... end
    # generator_for :foo, value
    # generator_for :foo => value
    # generator_for :foo, :class => GeneratorClass
    # generator_for :foo, :object => Generator instance
    # generator_for :foo, :method => :method_name
    def generator_for(handle, args = {}, &block)
      if handle.is_a?(Hash)
        raise ArgumentError, "only specify one attr => value pair at a time" unless handle.keys.length == 1
        gen_data = handle
        handle = gen_data.keys.first
        args = gen_data[handle]
      end
      
      raise ArgumentError, "an attribute name must be specified" unless handle = handle.to_sym
      
      unless args.is_a?(Hash)
        unless block
          retval = args #capture args before it becomes a hash
          block = if generator?(args)
            lambda {retval.next}
          else
            lambda {retval}
          end
        end
        args = {}  # args is assumed to be a hash for the rest of the method
      end
      
      if args[:method]
        raise ArgumentError, "generator method :[#{args[:method]}] is not known" unless respond_to?(args[:method].to_sym)
        record_generator_for(handle, :method => args[:method].to_sym)
      elsif args[:class]
        raise ArgumentError, "generator class [#{args[:class].name}] does not have a :next method" unless args[:class].respond_to?(:next)
        record_generator_for(handle, :class => args[:class])
      elsif args[:object]
        raise ArgumentError, "generator instance [#{args[:object]}] does not have a :next method" unless args[:object].respond_to?(:next)
        record_generator_for(handle, :object => args[:object])
      elsif block
        raise ArgumentError, "generator block must take an optional single argument" unless (-1..1).include?(block.arity)  # NOTE: lambda {} has an arity of -1, while lambda {||} has an arity of 0
        h = { :block => block }
        h[:start] = args[:start] if args[:start]
        record_generator_for(handle, h)
      else
        raise ArgumentError, "a block, :class generator, :method generator, :object generator, or value must be specified to generator_for"
      end
    end
    
    def generator?(args)
      args.class.to_s =~ /Generator/
    end

    def generation_strategy_for(name, &strategy)
      @current_strategy = name
      instance_eval &strategy
    ensure
      @current_strategy = nil
    end
    
    def generators_for(strategy)
      return generators unless strategy
      raise ArgumentError, "generation strategy [#{strategy}] is not defined" unless generation_strategies[strategy]
      generators.merge(generation_strategies[strategy])
    end
    
    def gather_exemplars
      return if exemplars_generated
      if superclass.respond_to?(:gather_exemplars)
        superclass.gather_exemplars
        self.generators = (superclass.generators || {}).dup
      end
      
      path = File.join(exemplar_path, "#{underscore(name)}_exemplar.rb")
      load(path) if File.exists?(path)
      self.exemplars_generated = true
    end
    
    def presence_validated_attributes
      @presence_validated_attributes ||= {}
      attrs = @presence_validated_attributes
      if superclass.respond_to?(:presence_validated_attributes)
        attrs = superclass.presence_validated_attributes.merge(attrs)
      end
      attrs
    end
    
  protected
  
    # we define an underscore helper ourselves since the ActiveSupport isn't available if we're not using Rails
    def underscore(string)
      string.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end
    
    def record_generator_for(handle, generator, strategy = @current_strategy ||= :base)
      self.generation_strategies ||= {}
      generation_strategies[strategy] ||= {}
      self.generators ||= {}
      if (generation_strategies[strategy][handle] || {})[:source] == self
        raise ArgumentError, "a generator for attribute [:#{handle}] has already been specified"
      end
      gen = { :generator => generator, :source => self }
      generators[handle] = gen if strategy == :base
      generation_strategies[strategy][handle] = gen
    end
  end
  
  module RailsClassMethods
    def exemplar_path
      File.join(RAILS_ROOT, 'test', 'exemplars')
    end
    
    def validates_presence_of_with_object_daddy(*attr_names)
      @presence_validated_attributes ||= {}
      new_attr = attr_names.dup
      new_attr.pop if new_attr.last.is_a?(Hash)
      new_attr.each {|a| @presence_validated_attributes[a] = true }
      validates_presence_of_without_object_daddy(*attr_names)
    end
    
    def generate(*args)
      obj = spawn(*args)
      obj.save
      obj
    end
    
    def generate!(*args)
      obj = spawn(*args)
      obj.save!
      obj
    end
  end
end
