# namespace :delegates do
#   desc "Generate temporary passwords for all delegates without passwords"
#   task generate_passwords: :environment do
#     delegates_without_password = Delegate.where(password_digest: nil).limit(10)
    
#     delegates_without_password.each do |delegate|
#       temp_password = delegate.generate_temporary_password
      
#       # แสดงผลในคอนโซล
#       puts "Delegate: #{delegate.email || 'N/A'}"
#       puts "Name: #{delegate.name}"
#       puts "Temporary Password: #{temp_password}"
#       puts "-" * 50
#     end
    
#     puts "Generated passwords for #{delegates_without_password.count} delegates"
#   end
  
#   desc "Generate password for specific delegate by email"
#   task :generate_password, [:email] => :environment do |t, args|
#     email = args[:email]
    
#     if email.blank?
#       puts "Usage: rake delegates:generate_password[email]"
#       next
#     end
    
#     delegate = Delegate.find_by(email: email)
    
#     if delegate.nil?
#       puts "Delegate with email #{email} not found"
#       next
#     end
    
#     temp_password = delegate.generate_temporary_password
    
#     puts "Delegate: #{delegate.email}"
#     puts "Name: #{delegate.name}"
#     puts "Temporary Password: #{temp_password}"
#     puts "Password generated successfully!"
#   end
# end


# namespace :delegates do
#   desc "Generate temporary passwords for all delegates without passwords"
#   task generate_passwords: :environment do
#     delegates_without_password = Delegate.where(password_digest: nil)

#     if delegates_without_password.empty?
#       puts "No delegates without passwords found"
#       next
#     end

#     delegates_without_password.find_each do |delegate|
#       temp_password = delegate.generate_temporary_password

#       puts "Delegate: #{delegate.email || 'N/A'}"
#       puts "Name: #{delegate.name}"
#       puts "Temporary Password: #{temp_password}"
#       puts "-" * 50
#     end

#     puts "Generated passwords for #{delegates_without_password.count} delegates"
#   end
# end



# lib/tasks/delegates.rake
namespace :delegates do
  desc "Generate temporary passwords for 3 delegates (overwrite existing passwords)"
  task generate_test_passwords: :environment do
    delegates = Delegate.order(Arel.sql('RANDOM()')).limit(3)

    if delegates.empty?
      puts "No delegates found"
      next
    end

    delegates.each do |delegate|
      temp_password = delegate.generate_temporary_password(overwrite: true)

      puts "Delegate ID: #{delegate.id}"
      puts "Email: #{delegate.email || 'N/A'}"
      puts "Name: #{delegate.name}"
      puts "Temporary Password: #{temp_password}"
      puts "-" * 50
    end

    puts "✅ Generated test passwords for #{delegates.size} delegates (OVERWRITTEN)"
  end
end
