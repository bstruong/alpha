
begin
  # config/initializers/check_ruby_version.rb
  require 'rubygems'
  
  min_ruby_version = Gem::Version.new(Rails.version.split('.').first(2).join('.'))
  current_ruby_version = Gem::Version.new(RUBY_VERSION)
  
  if current_ruby_version < min_ruby_version
    raise "Ruby version is too low. Minimum required: #{min_ruby_version}, Current: #{current_ruby_version}"
  end
  puts "RESULT: PASS"
rescue => e
  puts "RESULT: FAIL: exception loading initializer: #{e.class}: #{e.message}"
end
