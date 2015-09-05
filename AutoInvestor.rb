#!/usr/bin/ruby

require 'yinum'
require 'rest-client'
require 'json'
require 'pp'
require 'washbullet'
require 'configatron'
require 'byebug'
require './configatron.rb'

#  TODO:
#  Exclude loans already invested in


$debug = true


class Account

	def availableCash
		@availableCash ||= Account.GetAvailableCash
	end

	def self.GetAvailableCash
		methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/availablecash"
		if $debug
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


class Loans
	
	TERMS = Enum.new(:TERMS, :months60 => 60, :months36 => 36)
	PURPOSES = Enum.new(:PURPOSES, :credit_card_refinancing => 'credit_card_refinance', :consolidate => 'debt_consolidation', :other => 'other', :credit_card => 'credit_card', :home_improvement => 'home_improvement', :small_business => 'small_business')

	def purchasLoans
		filterLoans(loanList)
		placeOrder(buildOrderList)
		PB.sendMessage # send PushBullet message
	end

	def loanList
		@loanList ||= Loans.GetAvailableLoans
	end

	def self.GetAvailableLoans
		methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/loans/listing"
		if $debug
			puts "Pulling fresh Loans data."
			puts "methodURL: #{__method__} -> #{methodURL}"
		end

		begin
			response = RestClient.get( methodURL, 
			 		"Authorization" => configatron.lending_club.authorization,
			 		"Accept" => configatron.lending_club.content_type,
			 		"Content-Type" => configatron.lending_club.content_type
				)
			result = JSON.parse(response)
			PB.addLine("Pre-Filtered Loan Count:  #{result.values[1].size}")
		rescue
			PB.addline("Failure in: #{__method__}\nUnable to get a list of available loans.")
		end
		return result 
	end	 

	def filterLoans(loanList)
		@loanList = loanList.values[1].select do |o|
			o["term"].to_i == TERMS.months36 && 
			o["annualInc"].to_i / 12 > 3000 &&
			o["empLength"].to_i > 23 &&
			o["inqLast6Mths"].to_i == 1 &&
			o["pubRec"].to_i == 0 &&
			o["intRate"].to_f < 27.0 &&
			o["intRate"].to_f > 15.5 &&
			o["dti"].to_i <= 20 &&
			o["delinq2Yrs"].to_i < 4 &&
			( 	# exclude loans where the installment amount is more than 10% of the borrower's monthly income
				o["installment"].to_f / (o["annualInc"].to_f / 12) < 0.1 
			) &&
			(
				o["purpose"].to_s == PURPOSES.credit_card || 
				o["purpose"].to_s == PURPOSES.credit_card_refinancing ||
				o["purpose"].to_s == PURPOSES.consolidate
			)
		end
		
		@loanList.sort! { |a,b| b["intRate"].to_f <=> a["intRate"].to_i }
	 	
	 	if $debug
	 		puts "Filtered Loan List:"
	 		pp @loanList 	 	
	 	end

		PB.addLine("Post-Filtered Loan Count:  #{@loanList.size}")
	end

	def buildOrderList
		purchasableLoanCount = [Loans.PurchasableLoanCount, @loanList.size].min 

		PB.addLine("Attempting to purchas #{purchasableLoanCount} loans.")

		if purchasableLoanCount > 0
			orderList = Hash["aid" => $account, "orders" => 
				@loanList.first(Loans.PurchasableLoanCount).map do |o|
					Hash[
							'loanId' => o["id"].to_i,
						 	'requestedAmount' => configatron.lending_club.investment_amount, 
						 	'portfolioId' => configatron.lending_club.portfolio_id
						]
				end
			]
		end
		return orderList
	end

	def self.PurchasableLoanCount
		A.availableCash.to_i / configatron.lending_club.investment_amount 
	end

	def placeOrder(orderList)

		if orderList != nil
		 	methodURL = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/orders"
		 	if $debug
		 		puts "Placing purchas order."
		 		puts "methodURL: #{__method__} -> #{methodURL}"
		 	end

		 	begin
			 	response = RestClient.post(methodURL, orderList.to_json,
			 		"Authorization" => configatron.lending_club.authorization,
			 		"Accept" => configatron.lending_club.content_type,
			 		"Content-Type" => configatron.lending_club.content_ype
			 		)
				
				PB.setSubject "#{response.values[1].select { |o| o["executionStatus"].include? 'ORDER_FULFILLED' }.size} of #{Loans.PurchasableLoanCount}"
				PB.addLine "Successfully Invested: $#{response.values[1].select { |o| o["executionStatus"].include? 'ORDER_FULFILLED' }.inject(0) { |sum, o| sum + o["investedAmount"] } }"
			rescue
				PB.addline("Failure in: #{__method__}\nUnable to place order.")
			end
		else
	 		PB.setSubject "0 of #{Loans.PurchasableLoanCount}"
	 		PB.addLine "0 loans purchased."
	 	end
	end
end


class PushBullet
	def initialize
		@client ||= PushBullet.initializePushBulletClient
		addLine(Time.now.strftime("%H:%M %d/%m/%Y"))
	end

	def self.initializePushBulletClient
		Washbullet::Client.new(configatron.push_bullet.api_key)
	end

	def addLine(line)
		@message = "#{@message}\n#{line}"
	end
	
	def setSubject(purchasCount)
		@subject = "Lending Club AutoInvestor - #{purchasCount} purchases"
	end

	def sendMessage
		if $debug
	 		puts "PushBullet Message:"
	 		puts viewMessage
	 	end

	 	begin 
			@client.push_note(receiver: configatron.bush_bullet.device_id, params: { title: @subject, body: @message } )
		rescue
			puts "Failure in: #{__method__}\nUnable to send the following PushBullet note:\n"
			puts viewMessage
		ensure
			@client = nil
		end
	end

	def viewMessage
		puts "Subject:  #{@subject}"
		puts "Message:  #{@message}"
	end
end


PB = PushBullet.new
A = Account.new
L = Loans.new


L.purchasLoans




