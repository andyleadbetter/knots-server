begin
	require 'lib/db'
	require 'lib/common'
rescue	Exception => ex
	puts "This script must be run from the knots root"
	exit
end
require 'fileutils'
@db = Common.load_database(false)
puts "use the @db variable to access the database"
