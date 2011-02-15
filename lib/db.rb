#!/usr/bin/env ruby
require 'rubygems'
require 'sqlite3'
if RUBY_VERSION < "1.9"
	require 'lib/ohash'
else
	require 'lib/ohash2'
end
include SQLite3
require 'rexml/document'
include REXML

class KnotsArray < Array
	
	def to_yaml
		h = OrderHash.new
		self.each_with_index do | row, i |
			if row.get_table_name
				h[i] = row.fields
			else
				h[-1] = Hash.new if !h[-1]
				h[-1] = h[-1].replace(row.fields)
			end
		end
		h.to_yaml
	end
	
	def to_xml
		doc = Document.new("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>")
		root = doc.add_element("root")
		items = root.add_element("items")
		self.each_with_index do | row, i |
			elem = items.add_element("item")
			row.fields.each_pair do | key, value |
				value = CData.new(value) if value.instance_of?(String) 
				elem.add_element(key).text =  value
			end
		end
		doc
	end
	
	def combine(key, value = nil)
		combined = value ? OrderHash.new : KnotsArray.new
		each do | row |
			combined[row.fields[key]] = row.fields[value] if value
			combined.push(row.fields[key]) if !value
		end
		combined
	end
end

class KnotsDB
	
	def initialize(database)
		@db = Database.new(database)
		@db.type_translation = true
	end
	
	def vacuum
		@db.execute2("VACUUM")
	end
	
	def execute(query)
		begin
			@db.execute2(query)
			true
		rescue Exception => ex
			false
		end
	end
	
	def get_table(table_name)
		rows = @db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name='#{table_name}'" )
		return rows.size == 1 ? KnotsDBTable.new(table_name, @db) : nil
	end
	
	def tables
		tables = KnotsArray.new
		rows = @db.execute("select tbl_name FROM sqlite_master WHERE tbl_name NOT LIKE '%sqlite%'")
		rows.each do | row |
			tables.push(get_table(row[0]))
		end
		return tables
	end
	
	def method_missing(method_id, *arguments)
		# Tries to find the table KnotsDB.<table_name> and returns a KnotsDBTable if found or nil if not found
		return get_table(method_id.to_s)
	end
end

class KnotsDBTable
	
	def initialize(name, db)
		@name = name
		@db = db
	end
	
	def self.from_yaml(str, name, db)
		items = KnotsArray.new
		YAML.load(str).each do | val |
			items.push(KnotsDBRow.from_yaml(val.to_yaml, name, db))
		end
		return items
	end
	
	def method_missing(method_id, *arguments)
		# Parses KnotsDB.KnotsDBTable.requests and generates a query
		method_name = method_id.to_s
		tokens = method_name.split("_")
		query_type = tokens.shift
		query = nil
		options = nil
		if query_type == "by" || query_type == "delete"
			options = arguments[1] || OrderHash.new
			field = tokens.join("_")
			operator, value = parse_operator(arguments[0]) if arguments[0]
			query = "#{query_type == "by" ? "select *" : "delete"} from #{self.get_table_name}"
			if !value
				query += " WHERE #{field} IS NULL"
			elsif value.instance_of?(String)
				query += " WHERE #{field} #{operator} #{value}"
			elsif value.instance_of?(Hash)
				query += " WHERE #{value[:conditions]}"
				options = value
			else
				query += " WHERE #{field} #{operator} #{value}"
			end
		elsif query_type == "all"
			options = arguments[0] || OrderHash.new
			query = "select * from #{self.get_table_name}"
		elsif query_type == "sql"
			options = arguments[1] || OrderHash.new
			query = arguments[0]
		end
		if options
			query += " ORDER BY #{options[:order]}" if options[:order]
			query += " OFFSET #{options[:offset]}" if options[:offset]
			query += " LIMIT #{options[:limit]}" if options[:limit]
		end
		if query
			t = Time.now
			items = KnotsArray.new
			columns, *rows = @db.execute2(query)
			t2 = Time.now
			rows.each do | row |
				fields = OrderHash.new
				row.each_with_index do | value, i |
					fields[columns[i].strip] = value
				end
				items.push(KnotsDBRow.new(self.get_table_name, @db, fields))
			end
			return items
		end
		return nil
	end
	
	def clear
		@db.execute2("DELETE FROM #{self.get_table_name}")
	end
	
	def size
		row = @db.execute2("SELECT count(id) AS size FROM #{self.get_table_name}")
		return row[1][0].to_i
	end
	
	def new
		fields = OrderHash.new
		columns, *rows = @db.execute2("SELECT * FROM #{self.get_table_name} LIMIT 1")
		columns.each do | column |
			fields[column] = nil
		end
		fields["id"] = nil
		return KnotsDBRow.new(self.get_table_name, @db, fields)
	end
	
	def get_table_name
		return @name
	end
	
	def parse_operator(str)
		if str.instance_of?(String)
			tokens = str.scan(/(IS|=|LIKE|!=|>=|<=|<|>)(.{0,})/i).flatten.collect!{|x| x = x.strip}
			return tokens.size == 2 ? tokens : ["=", !str.index("\"") ? "\"#{str}\"" : str]
		elsif str.instance_of?(Time)
			return ["=", str]
		else
			return ["=", str]
		end
	end
end

class KnotsDBRow
	
	def initialize(name, db, fields)
		@db = db
		@fields = fields
		@name = name
		@new_bindings = false
		begin
			@new_bindings = SQLite3::Version::VERSION >= "1.3.1"
		rescue Exception => ex
		end
	end
	
	def self.from_yaml(str, name, db)
		item = YAML.load(str)
		return KnotsDBRow.new(name, db, item)
	end
	
	def method_missing(method_id, *arguments)
		method_name = method_id.to_s.strip
		if method_name.index("=")
			field = method_name.gsub("=", "").strip
			if field != "id"
				@fields[field] = arguments.size == 1 ? arguments[0] : arguments if @fields.has_key?(field)
			end
		else
			return @fields[method_name]
		end
	end
	
	def id
		return @fields["id"] 
	end
	
	def save
		# Hash doesn't preserve order so we need to make sure the keys and values are in same order
		keys = @fields.keys
		values = KnotsArray.new
		keys.each do | key |
			if @new_bindings && (@fields[key].instance_of?(DateTime) || @fields[key].instance_of?(Date) || @fields[key].instance_of?(Time))
				@fields[key] = @fields[key].to_s
			end
			values.push(@fields[key])
		end
		if id
			@db.execute("UPDATE #{self.get_table_name} SET #{keys.collect{|x| x = "#{x} = ?"}.join(",")} WHERE id=#{id}", values)
		else
			@db.execute("INSERT INTO #{self.get_table_name} (#{keys.join(",")}) values(#{keys.collect{|x| x = "?"}.join(",")})", values)
			@fields["id"] = @db.execute("SELECT last_insert_rowid()")[0][0]
		end
	end
	
	def set_fields(fields)
		@fields = fields
	end
	
	def fields
		return @fields
	end
	
	def data_to_blob(data)
		return Blob.new(data)
	end
	
	def file_to_blob(filename)
		return data_to_blob(File.read(filename))
	end
	
	def delete
		if id
			@db.execute("DELETE FROM #{self.get_table_name} WHERE id=#{self.id}")
			@fields = OrderHash.new
		end
	end
	
	def get_table_name
		return @name
	end
	
end

