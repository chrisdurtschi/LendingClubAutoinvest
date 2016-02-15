require 'clockwork'
require_relative 'auto_investor.rb'

module Clockwork

	configure do |config|
		config[:sleep_timeout] = 1
		#config[:logger] = Logger.new(log_file_path)
		config[:tz] = 'UTC'
		config[:max_threads] = 15
		config[:thread] = false
	end
end

#LeningClub releases new loas at these times (UTC) each day
Clockwork.every(1.days, 'auto_investor.rb', :at => ['14:00', '18:00', '22:00', '02:00']) do

	PB = PushBullet.new
	A = Account.new

	Loans.new.purchase_loans
	sleep(3)
	Loans.new.purchase_loans
	sleep(5)
	Loans.new.purchase_loans

end
