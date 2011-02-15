
require './knots'


if !ENV["USER"] || ENV["USER"] != "root"
  k = Knots.new
  k.start
else
  puts("Don't run Knots as root.")
end
