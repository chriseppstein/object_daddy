require 'fileutils'

%w(test spec).detect do |test_or_spec|
  dir = File.dirname(__FILE__) + "/../../../#{test_or_spec}"
  dir = nil unless File.directory?(dir)
end
  
FileUtils.mkdir("#{dir}/exemplars") unless File.directory?("#{dir}/exemplars") if dir

puts IO.read(File.join(File.dirname(__FILE__), 'README'))
