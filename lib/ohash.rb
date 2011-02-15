require 'yaml'
require 'rexml/document'
include REXML

class OrderHash
  include Enumerable

  
	def to_yaml( opts = {} )
		YAML::quick_emit( object_id, opts ) do |out|
			out.map( taguri, to_yaml_style ) do |map|
				each do |k, v|
					map.add( k, v )
				end
			end
		end
	end
	
	def to_xml
		doc = Document.new("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>")
		root = doc.add_element("root")
		items = root.add_element("items")
		elem = items.add_element("item")
		self.each_pair do | key, value |
			value = CData.new(value) if value.instance_of?(String) 
			elem.add_element(key).text =  value
		end
		doc
	end

  def initialize(*args, &block)
    @h = Hash.new(*args, &block)
    @ordered_keys = []
  end

  def []=(key, val)
    @ordered_keys << key unless @h.has_key? key
    @h[key] = val
  end

  def each
    @ordered_keys.each {|k| yield(k, @h[k])}
  end
  alias :each_pair :each

  def each_value
    @ordered_keys.each {|k| yield(@h[k])}
  end

  def each_key
    @ordered_keys.each {|k| yield k}
  end

  def keys
    @ordered_keys
  end

  def values
    @ordered_keys.map {|k| @h[k]}
  end

  def clear
    @ordered_keys.clear
    @h.clear
  end

  def delete(k, &block)
    @ordered_keys.delete k
    @h.delete(k, &block)
  end

  def reject!
    del = []
    each_pair {|k,v| del << k if yield k,v}
    del.each {|k| delete k}
    del.empty? ? nil : self
  end

  def delete_if(&block)
    reject!(&block)
    self
  end

  %w(merge!).each do |name|
    define_method(name) do |*args|
      raise NotImplementedError, "#{name} not implemented"
    end
  end

  def method_missing(*args)
    method_name = args[0].to_s.strip
    if @h && @h.methods && @h.methods.include?(method_name)
	    @h.send(*args)
    else
	if method_name.index("=")
		args.shift
		@h[method_name.gsub("=", "").strip] = args.size > 1 ? args : args[0]
	elsif method_name.index("?")
		return @h.has_key?(method_name.gsub("?", "").strip)
	else
		return @h[method_name]
	end
    end
  end
end
