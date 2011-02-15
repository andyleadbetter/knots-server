require 'yaml'
require 'rexml/document'
include REXML

class String
	def each
		enum_for(:lines)
	end
end


class OrderHash < Hash

  
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


	def method_missing(*args)
		method_name = args[0].to_s.strip
		if method_name.index("=")
			args.shift
			self[method_name.gsub("=", "").strip] = args.size > 1 ? args : args[0]
		elsif method_name.index("?")
			return self.has_key?(method_name.gsub("?", "").strip)
		else
			return self[method_name]
		end
	end
end
