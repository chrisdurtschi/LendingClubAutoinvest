#!/usr/bin/ruby

require 'yinum'
require 'rest-client'
require 'json'
require 'pp'
require 'byebug'
require 'pushbullet'


# curl -v -H "Accept: application/json" -H "Authorization: 6aRjEtqDjvu6zGqAlj13dzZkDf4=" -H "Content-Type: application/json" -X GET "https://api.lendingclub.com/api/investor/v1/loans/listing"
# curl -v -H "Accept: application/json" -H "Authorization: 6aRjEtqDjvu6zGqAlj13dzZkDf4=" -H "Content-Type: application/json" -X GET "https://api.lendingclub.com/api/investor/v1/accounts/2628791/availablecash"

# LendingClub Configurations #
$debug = true
$authorization = '6aRjEtqDjvu6zGqAlj13dzZkDf4='
$account = 2628791
$accountURL = "/accounts/#{$account}"
$apiVersion = '/v1'
$baseURL = "https://api.lendingclub.com/api/investor#{$apiVersion}"
$contentType = 'application/json'

$portfolioId = 59612258  	# Autoinvestor
$investmentAmount = 25 		# amount to invest per loan ($25 minimum)

#PushBullet
$pushbulletApiKey = 'HwqGqblxJUqoQ1SPcYsLpew9APBBnDXZ'
$deviceId = 'ujweNd5igMesjAiVsKnSTs' #iphone 5s


TERMS = Enum.new(:TERMS, :months60 => 60, :months36 => 36)
PURPOSES = Enum.new(:PURPOSES, :credit_card_refinancing => 'credit_card_refinance', :consolidate => 'debt_consolidation', :other => 'other', :credit_card => 'credit_card', :home_improvement => 'home_improvement')

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

		response = RestClient.get(methodURL, 
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
			#o["term"].to_i == TERMS.months36 && 
			o["annualInc"].to_i / 12 > 3000 &&
			o["empLength"].to_i > 23 &&
			o["inqLast6Mths"].to_i == 1 &&
			o["pubRec"].to_i == 0 &&
			o["intRate"].to_i < 19.0 &&
			#o["intRate"].to_i > 12.5 &&
			o["dti"].to_i <= 20 &&
			o["delinq2Yrs"].to_i == 0 &&
			(
				( o["installment"].to_i / (o["annualInc"].to_i / 12) ) < 0.8
			) &&
			(
				o["purpose"].to_s == PURPOSES.credit_card || 
				o["purpose"].to_s == PURPOSES.credit_card_refinancing ||
				o["purpose"].to_s == PURPOSES.consolidate
			).to_json
		end
		pp @availableLoans.sort { |a,b| b["intRate"].to_f <=> a["intRate"].to_i }

		#pp @availableLoans = @availableLoans.sort! do |k| k["intRate"] end 
		#pp @availableLoans.sort {|k,v| v['intRate']}
		PBC.addLine("Post-Filtered Loan Count:  #{@availableLoans.size}")
	end

	def buildOrderList
		purchasableLoanCount = Loans.PurchasableLoanCount
		PBC.addLine("Attempting to purchas #{purchasableLoanCount} loans.")

		if purchasableLoanCount > 0
			@Orders = Hash["aid" => $account, "orders" => 
				@availableLoans.map do |o|
					Hash[
							'loanId' => o["id"].to_i,
						 	'requestedAmount' => $investmentAmount, 
						 	'portfolioId' => $portfolioId,
						 	'intRate' => o["intRate"]
						]
				end
			]
		pp @Orders

			#@Orders = @Orders.sort_by { |k,v| v['intRate'] }
		else
			@Orders = nil
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
			# methodURL = "#{$baseURL}#{$accountURL}/orders"
			# if $debug
			# 	puts "methodURL: #{__method__} -> #{methodURL}"
			# end

			# response = RestClient.post(methodURL, @Orders.to_json,
			# 	"Authorization" => $authorization,
			# 	"Accept" => $contentType,
			# 	"Content-Type" => $contentType
			# )

			# puts "Response size:  #{response.size}"
		 #   	puts "Response:  #{response.to_str}"
		 #   	puts "Response status: #{response.code}"
		 #   	response.headers.each { |k,v|
		 #   		puts "Header: #{k}=#{v}"
		 #   	}
		
		end

		#pp JSON.parse(response)
	end
end


class PushBullet
	def pushBulletClient
		@client |= initializePushBulletClient
	end

	def self.initializePushBulletClient
		Pushbullet::Client.new($pushbulletApiKey)
	end

	def addLine(line)
		@message = "#{@message}\r\n#{line}"
	end
	
	def sendMessage
		client.push_note($ujweNd5igMesjAiVsKnSTs, 'Lending Club AutoInvestor Update', @message)
	end

	def viewMessage
		@message
	end
end


A = Account.new
L = Loans.new
PBC = PushBullet.new	

pp A.availableCash
L.availableLoans
L.filterLoans
#p L.buildOrderList
#L.placeOrder
puts "PCB Message:  #{PBC.viewMessage}"


