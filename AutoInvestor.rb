#!/usr/bin/ruby

require 'yinum'
require 'rest-client'
require 'json'
require 'pp'
require 'washbullet'
require 'byebug'

#  TODO:
#  Exclude loans already invested in
#  Implement PushBullit notifications

# LendingClub Configurations #
$debug = true
$authorization = ''
$account = 2628791
$accountURL = "/accounts/#{$account}"
$apiVersion = '/v1'
$baseURL = "https://api.lendingclub.com/api/investor#{$apiVersion}"
$contentType = 'application/json'

$portfolioId = 59612258  	# Autoinvestor
$investmentAmount = 25 		# amount to invest per loan ($25 minimum)

#PushBullet
$pushbulletApiKey = ''
$deviceId = '' #iphone 5s


TERMS = Enum.new(:TERMS, :months60 => 60, :months36 => 36)
PURPOSES = Enum.new(:PURPOSES, :credit_card_refinancing => 'credit_card_refinance', :consolidate => 'debt_consolidation', :other => 'other', :credit_card => 'credit_card', :home_improvement => 'home_improvement', :small_business => 'small_business')

class Account

	def availableCash
		@availableCash ||= Account.GetAvailableCash
	end

	def self.GetAvailableCash
		methodURL = "#{$baseURL}#{$accountURL}/availablecash"
		if $debug
			puts "methodURL: #{__method__} -> #{methodURL}"
		end

		response = RestClient.get(methodURL,
			"Authorization" => $authorization,
			"Accept" => $contentType,
			"Content-Type" => $contentType
		)
		
		result = JSON.parse(response)['availableCash']
		PBC.addLine("Available Cash:  #{result}")
		return result
	end
end


class Loans
	
	def availableLoans
		@availableLoans ||= Loans.GetAvailableLoans
	end

	def self.GetAvailableLoans
		methodURL = "#{$baseURL}/loans/listing"
		if $debug
			puts "Pulling fresh Loans data."
			puts "methodURL: #{__method__} -> #{methodURL}"
		end

		response = RestClient.get( methodURL, 
			"Authorization" => $authorization,
			"Accept" => $contentType,
			"Content-Type" => $contentType
		)
		
		result = JSON.parse(response)
		PBC.addLine("Pre-Filtered Loan Count:  #{result.values[1].size}")
		return result 
	end	

	def filterLoans 
		@availableLoans = @availableLoans.values[1].select do |o|
			o["term"].to_i == TERMS.months36 && 
			 o["annualInc"].to_i / 12 > 3000 &&
			 o["empLength"].to_i > 23 &&
			 o["inqLast6Mths"].to_i == 1 &&
			 o["pubRec"].to_i == 0 &&
			 o["intRate"].to_f < 27.0 &&
			o["intRate"].to_f > 15.5 &&
			o["dti"].to_i <= 20 &&
			o["delinq2Yrs"].to_i < 4 &&
			( 	# exclude loans where the installment amount is more than 10% of the borrowers monthly income
				o["installment"].to_f / (o["annualInc"].to_f / 12) < 0.1 
			) &&
			(
				o["purpose"].to_s == PURPOSES.credit_card || 
				o["purpose"].to_s == PURPOSES.credit_card_refinancing ||
				o["purpose"].to_s == PURPOSES.consolidate
			)
		end
		@availableLoans.sort! { |a,b| b["intRate"].to_f <=> a["intRate"].to_i }
	 	
	 	if $debug
	 		pp @availableLoans 
	 	end
		
		PBC.addLine("Post-Filtered Loan Count:  #{@availableLoans.size}")
	end

	def buildOrderList
		purchasableLoanCount = [Loans.PurchasableLoanCount, @availableLoans.size].min 

		PBC.addLine("Attempting to purchas #{purchasableLoanCount } loans.")

		if purchasableLoanCount > 0
			@Orders = Hash["aid" => $account, "orders" => 
				@availableLoans.first(Loans.PurchasableLoanCount).map do |o|
					Hash[
							'loanId' => o["id"].to_i,
						 	'requestedAmount' => $investmentAmount, 
						 	'portfolioId' => $portfolioId
						]
				end
			]
		end
	end

	def self.PurchasableLoanCount
		A.availableCash.to_i / $investmentAmount 
	end

	def placeOrder

		if @Orders == nil
			puts "No loans to purchase."
			return
		else
		 	methodURL = "#{$baseURL}#{$accountURL}/orders"
		 	if $debug
		 		puts "methodURL: #{__method__} -> #{methodURL}"
		 	end

		 	#response = {}
		 	response = RestClient.post(methodURL, @Orders.to_json,
		 		"Authorization" => $authorization,
		 		"Accept" => $contentType,
		 		"Content-Type" => $contentType
		 		)

			PBC.addLine "Successfully Invested: $#{response.values[1].select { |o| o["executionStatus"].include? 'ORDER_FULFILLED' }.inject(0) { |sum, o| sum + o["investedAmount"] } }"
	 	end
	end
end


class PushBullet
	def initialize
		@client ||= PushBullet.initializePushBulletClient
	end

	def self.initializePushBulletClient
		Washbullet::Client.new($pushbulletApiKey)
	end

	def addLine(line)
		@message = "#{@message}\r\n#{line}"
	end
	
	def sendMessage
	#	@client.push_note($deviceId, , params: { title: 'Lending Club AutoInvestor Update', body: @message } )
	end

	def viewMessage
		puts @message
	end
end


A = Account.new
L = Loans.new
PBC = PushBullet.new	

A.availableCash
L.availableLoans
L.filterLoans
L.buildOrderList
L.placeOrder
puts "PCB Message:"
PBC.viewMessage
#PBC.sendMessage


