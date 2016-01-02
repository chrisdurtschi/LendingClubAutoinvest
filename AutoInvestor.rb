#!/usr/bin/ruby

require_relative 'configatron.rb'
require 'rubygems'
require 'bundler/setup'
require 'yinum'
require 'rest-client'
require 'json'
require 'pp'
require 'washbullet' #PushBullet
require 'byebug'


#  TODO:
#  Add Setup Instructions
#  		Add instructons for using clock.rb with /etc/init.d/clockworker.sh
#  		Add instruction for using clockworkd and clockwork
# 		(recomend using foreman/upstart)
#  Implement Unit Tests
#  Identify and handle purchases when loans are released late 
# 		removes need to call purchase loans multiple times
#  Improve order response messaging
# 		I.e. handle all response codes
#  Consider pulling loan value prior to release then sleeping until release

###############################
#  Install Instructions:
#  	Rotate logs using logrotate
#		brew install logrotate (OS X only)
#		mkdir /var/log/lending_club_autoinvestor/
#		add below to "/etc/logrotate.d/lending_club_autoinvestor" file:
#			/var/log/lending_club_autoinvestor/*.log {
#		        daily
#		        missingok
#		        rotate 7
#		        compress
#		        notifempty
#				nocreate
#			}
#		modify configuration as needed (man logrotate)
###############################

###############################
#  	Notes:
# 	It's intended for this script to be scheduled to run each time LendingClub releases new loans. 
# 	Currently LendingClub releases new loans at 7 AM, 11 AM, 3 PM and 7 PM (MST) each day.
#   This is idealy handled by the clock.rb/clockworkd/colckworker.sh setup  
###############################

$debug = false 
$verbose = true


class Loans
	TERMS = Enum.new(:TERMS, :months60 => 60, :months36 => 36)
	PURPOSES = Enum.new(:PURPOSES, :credit_card_refinancing => 'credit_card_refinance', :consolidate => 'debt_consolidation', :other => 'other', :credit_card => 'credit_card', :home_improvement => 'home_improvement', :small_business => 'small_business')

	def purchaseLoans
		filterLoans(loanList)
		removeOwnedLoans(ownedLoans)
		placeOrder(buildOrderList)
		PB.sendMessage # send PushBullet message
		#PB.viewMessage
	end

	def loanList
		@loanList ||= Loans.getAvailableLoans
	end

	def self.getAvailableLoans
		methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/loans/listing" #only show loans released in the most recent release (add "?showAll=true" to see all loans)
		if $debug
			puts "Pulling loans from file: '#{configatron.testing_files.available_loans}'"
			response = File.read(File.expand_path("../" + configatron.testing_files.available_loans, __FILE__))
			return JSON.parse(response)
		else
			begin
	
				puts "Pulling fresh Loans data."
			 	puts "methodURL: #{__method__} -> #{methodURL}"
				response = RestClient.get( methodURL, 
				 		"Authorization" => configatron.lending_club.authorization,
				 		"Accept" => configatron.lending_club.content_type,
				 		"Content-Type" => configatron.lending_club.content_type
					)
				result = JSON.parse(response)
				PB.addLine("Pre-Filtered Loan Count:  #{result.values[1].size}")
			rescue
				PB.addLine("Failure in: #{__method__}\nUnable to get a list of available loans.")
			end
		end
		
		return result 
	end	 

	def filterLoans(loanList)
		unless loanList.nil?
			@loanList = loanList.values[1].select do |o|
				o["term"].to_i == TERMS.months36 && 
				o["annualInc"].to_f / 12 > 3000 &&
				o["empLength"].to_i > 23 && #
				o["inqLast6Mths"].to_i <= 1 &&
				o["pubRec"].to_i == 0 &&
				o["intRate"].to_f < 27.0 &&
				o["intRate"].to_f > 16.0 &&
				o["dti"].to_f <= 20.00 &&
				o["delinq2Yrs"].to_i < 4 &&
				( 	# exclude loans where the instalment amount is more than 10% of the borrower's monthly income
					o["installment"].to_f / (o["annualInc"].to_f / 12) < 0.1 
				) &&
				(
					o["purpose"].to_s == PURPOSES.credit_card || 
					o["purpose"].to_s == PURPOSES.credit_card_refinancing ||
					o["purpose"].to_s == PURPOSES.consolidate
				)
			end
			# sort the loans with the highest interst rate to the front  --this is so they will be purchased first when there aren't enough funds to purchase all loans
			@loanList.sort! { |a,b| b["intRate"].to_f <=> a["intRate"].to_i }
		end
	end

	def removeOwnedLoans(ownedLoans)
		unless @loanList.nil?
			# extract loanId's from a hash of already owned loans and remove those loans from the list of filtered loans
			a = []
			ownedLoans.values[0].map {|o| a << o["loanId"]}
			a.each { |i| @loanList.delete_if {|key, value| key["id"] == i} }
		end
	end
	
	def ownedLoans
		methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/notes"
		if $verbose
			puts "Pulling list of already owned loans."
			puts "methodURL: #{__method__} -> #{methodURL}"
		end

		begin 
			response = RestClient.get(methodURL,
			 		"Authorization" => configatron.lending_club.authorization,
			 		"Accept" => configatron.lending_club.content_type,
			 		"Content-Type" => configatron.lending_club.content_type
				)

			result = JSON.parse(response)

		rescue
			PB.addLine("Failure in: #{__method__}\nUnable to get the list of already owned loans.")
		end

		return result
	end
	
	def buildOrderList
		@purchasableLoanCount = [Loans.fundableLoanCount, @loanList.size].min 

		PB.addLine("Plancing an order for #{@purchasableLoanCount} loans.")

		if @purchasableLoanCount > 0
			orderList = Hash["aid" => configatron.lending_club.account, "orders" => 
				@loanList.first(@purchasableLoanCount).map do |o|
					Hash[
							'loanId' => o["id"].to_i,
						 	'requestedAmount' => configatron.lending_club.investment_amount, 
						 	'portfolioId' => configatron.lending_club.portfolio_id
						]
				end
			]
		end
		begin
			File.open(File.expand_path(configatron.logging.order_list_log), 'a') { |file| file.write("#{Time.now.strftime("%H:%M:%S %d/%m/%Y")}\n#{orderList}\n\n") }
		ensure
			return orderList
		end
	end

	def self.fundableLoanCount
		A.availableCash.to_i / configatron.lending_club.investment_amount 
	end

	def placeOrder(orderList)
	 	methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/orders"
	 	if $verbose
	 		puts "Placing purchase order."
	 		puts "methodURL: #{__method__} -> #{methodURL}"
	 	end
	 	if $debug
	 		puts "Debug mode - This order will NOT be placed."
	 		puts "Pulling loans from file: '#{configatron.testing_files.purchase_response}'"
		
			response = File.read(File.expand_path("../" + configatron.testing_files.purchase_response, __FILE__))
		else
			unless orderList.nil?
			  	begin
				  	response = RestClient.post(methodURL, orderList.to_json,
				  	 	"Authorization" => configatron.lending_club.authorization,
				  	 	"Accept" => configatron.lending_club.content_type,
				  	 	"Content-Type" => configatron.lending_club.content_type
				  	 	)
				rescue
					if $verbose
						puts "Order Response:  #{response}"
						puts "orderList: #{orderList}"
					end
					PB.addLine("Failure in: #{__method__}\nUnable to place order with methodURL:\n#{methodURL}")
					reportOrderResponse(nil) # order failed; enusure reporting
					return
				end
			end
		end
		reportOrderResponse(response)
	end

	def reportOrderResponse(response)

		unless response.nil?
				response = JSON.parse(response)
				File.open(File.expand_path(configatron.logging.order_response_log), 'a') { |file| file.write("#{Time.now.strftime("%H:%M:%S %d/%m/%Y")}\n#{response}\n\n") }
			begin
				puts "Response: #{response}"
				invested = response.values[1].select { |o| o["executionStatus"].include? 'ORDER_FULFILLED' }
				notInFunding = response.values[1].select { |o| o["executionStatus"].include? 'NOT_AN_IN_FUNDING_LOAN' }
				PB.setSubject("#{invested.size.to_i} of #{@purchasableLoanCount}/#{[Loans.fundableLoanCount.to_i, @loanList.size].max}")
				PB.addLine("Successfully Invested:  #{invested.inject(0) { |sum, o| sum + o["investedAmount"].to_f }}") # dollar amount invested
				if notInFunding.any?
					PB.addLine("No longer in funding:  #{notInFunding.size}") # NOT_AN_IN_FUNDING_LOAN
				end
			rescue
				if $verbose
					puts "Order Response:  #{response}"
				end
				PB.addLine("Failure in: #{__method__}\nUnable to report on order response.\nSee ~/Library/Logs/LC-PurchaseResponse.log for order response.")
			end
		else
			PB.setSubject "0 of #{@purchasableLoanCount}/#{[Loans.fundableLoanCount.to_i, @loanList.size].max}"
		end
	end

end


class Account

	def availableCash
		@availableCash ||= Account.getAvailableCash
	end

	def self.getAvailableCash
		methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/availablecash"
		if $verbose
			puts "Pulling list of available loans since last release."
			puts "methodURL: #{__method__} -> #{methodURL}"
		end

		begin 
			response = RestClient.get(methodURL,
			 		"Authorization" => configatron.lending_club.authorization,
			 		"Accept" => configatron.lending_club.content_type,		
			 		"Content-Type" => configatron.lending_club.content_type
				)

			result = JSON.parse(response)['availableCash']
			PB.addLine("Available Cash:  #{result}")
		rescue
			PB.addline("Failure in: #{__method__}\nUnable to get current account balance.")
		end
		
		return result
	end
end


class PushBullet

	def initialize
		pbClient
	end

	def pbClient
		@pbClient ||= PushBullet.initializePushBulletClient
		addLine(Time.now.strftime("%H:%M:%S %m/%d/%Y"))
	end

	def self.initializePushBulletClient
		Washbullet::Client.new(configatron.push_bullet.api_key)
	end

	def addLine(line)
		@message = "#{@message}\n#{line}"
	end
	
	def setSubject(purchasCount)
		@subject = "Lending Club AutoInvestor - #{purchasCount} purchased"
		if $debug
			@subject = "* DEBUG * " + @subject
		end
	end

	def sendMessage
		if $verbose
	 		puts "PushBullet Message:"
	 		puts viewMessage
	 	end

	 	begin 
			@pbClient.push_note(receiver: configatron.push_bullet.device_id, params: { title: @subject, body: @message } )
		rescue
			puts "Failure in: #{__method__}\nUnable to send the following PushBullet note:\n"
			puts viewMessage
		ensure
			#@pbClient = nil
			# setting @message and @subject to nil as setting @pbClient to nil does not appear to cause PushBullet.initializePushBulletClient to be called when next launched
			@message = nil
			@subject = nil
		end
	end

	def viewMessage
		puts "PushBullet Subject:  #{@subject}"
		puts "Message:  #{@message}"
	end
end
