
begin
  # config/initializers/check_ruby_version.rb
  
  class MinimumRubyVersionError < StandardError; end
  
  def check_ruby_version!
    required_ruby_version = Gem::Version.new('2.5.0') # Example minimum Ruby version
    current_ruby_version = Gem::Version.new(RUBY_VERSION)
    
    unless current_ruby_version >= required_ruby_version
      raise MinimumRubyVersionError, "This application requires Ruby #{required_ruby_version}. You are running Ruby #{current_ruby_version}."
    end
  end
  
  check_ruby_version!
  puts "RESULT: PASS"
rescue => e
  puts "RESULT: FAIL: exception loading initializer: #{e.class}: #{e.message}"
end
