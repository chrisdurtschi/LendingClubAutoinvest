require 'clockwork'
require_relative 'AutoInvestor.rb'

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
Clockwork.every(1.days, 'AutoInvestor.rb', :at => ['14:00', '18:00', '22:00', '02:00']){
	
	PB = PushBullet.new
	A = Account.new

	Loans.new.purchaseLoans
	sleep(3)
	Loans.new.purchaseLoans
	sleep(5)
	Loans.new.purchaseLoans

}
