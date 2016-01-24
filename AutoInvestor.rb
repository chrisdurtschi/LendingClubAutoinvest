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
# 		Removes need to call purchase loans multiple times
#  Improve order response messaging
# 		Currently only


###############################
#  Install Instructions:
#  	Rotate logs using logrotate
#		brew install logrotate (OS X only)
#		mkdir /var/log/lending_club_autoinvestor/
#		add below to "/etc/logrotate.d/lending_club_autoinvestor" file:
#			/var/log/lending_club_autoinvestor/*.log {
#		        weekly
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

$debug = true 
$verbose = true


class Loans
	TERMS = Enum.new(:TERMS, :months60 => 60, :months36 => 36)
	PURPOSES = Enum.new(:PURPOSES, :credit_card_refinancing => 'credit_card_refinance', :consolidate => 'debt_consolidation', :other => 'other', :credit_card => 'credit_card', :home_improvement => 'home_improvement', :small_business => 'small_business')

	def purchase_loans
		filter_loans(loan_list)
		remove_owned_loans(owned_loans)
		place_order(build_order_list)
		PB.send_message # send PushBullet message
		#PB.view_message
	end

	def loan_list
		@loan_list ||= Loans.get_available_loans
	end

	def self.get_available_loans
		method_url = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/loans/listing" #only show loans released in the most recent release (add "?showAll=true" to see all loans)
		if $debug
			puts "Pulling loans from file: '#{configatron.testing_files.available_loans}'"
			response = File.read(File.expand_path("../" + configatron.testing_files.available_loans, __FILE__))
			return JSON.parse(response)
		else
			begin
	
				puts "Pulling fresh Loans data."
			 	puts "method_url: #{__method__} -> #{method_url}"
				response = RestClient.get( method_url, 
				 		"Authorization" => configatron.lending_club.authorization,
				 		"Accept" => configatron.lending_club.content_type,
				 		"Content-Type" => configatron.lending_club.content_type
					)
				result = JSON.parse(response)
				PB.add_line("Pre-Filtered Loan Count:  #{result.values[1].size}")
			rescue
				PB.add_line("Failure in: #{__method__}\nUnable to get a list of available loans.")
			end
		end
		
		return result 
	end	 

	def filter_loans(loan_list)
		unless loan_list.nil?
			@loan_list = loan_list.values[1].select do |o|
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
			@loan_list.sort! { |a,b| b["intRate"].to_f <=> a["intRate"].to_i }
		end
	end

	def remove_owned_loans(owned_loans)
		unless @loan_list.nil?
			# extract loanId's from a hash of already owned loans and remove those loans from the list of filtered loans
			a = []
			owned_loans.values[0].map {|o| a << o["loanId"]}
			a.each { |i| @loan_list.delete_if {|key, value| key["id"] == i} }
		end
	end
	
	def owned_loans
		method_url = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/notes"
		if $verbose
			puts "Pulling list of already owned loans."
			puts "method_url: #{__method__} -> #{method_url}"
		end

		begin 
			response = RestClient.get(method_url,
			 		"Authorization" => configatron.lending_club.authorization,
			 		"Accept" => configatron.lending_club.content_type,
			 		"Content-Type" => configatron.lending_club.content_type
				)

			result = JSON.parse(response)

		rescue
			PB.add_line("Failure in: #{__method__}\nUnable to get the list of already owned loans.")
		end

		return result
	end
	
	def build_order_list
		@purchasable_loan_count = [Loans.fundable_loan_count, @loan_list.size].min 

		PB.add_line("Plancing an order for #{@purchasable_loan_count} loans.")

		if @purchasable_loan_count > 0
			order_list = Hash["aid" => configatron.lending_club.account, "orders" => 
				@loan_list.first(@purchasable_loan_count).map do |o|
					Hash[
							'loanId' => o["id"].to_i,
						 	'requestedAmount' => configatron.lending_club.investment_amount, 
						 	'portfolioId' => configatron.lending_club.portfolio_id
						]
				end
			]
		end
		begin
			File.open(File.expand_path(configatron.logging.order_list_log), 'a') { |file| file.write("#{Time.now.strftime("%H:%M:%S %d/%m/%Y")}\n#{order_list}\n\n") }
		ensure
			return order_list
		end
	end

	def self.fundable_loan_count
		A.available_cash.to_i / configatron.lending_club.investment_amount 
	end

	def place_order(order_list)
	 	method_url = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/orders"
	 	if $verbose
	 		puts "Placing purchase order."
	 		puts "method_url: #{__method__} -> #{method_url}"
	 	end
	 	if $debug
	 		puts "Debug mode - This order will NOT be placed."
	 		puts "Pulling loans from file: '#{configatron.testing_files.purchase_response}'"
		
			response = File.read(File.expand_path("../" + configatron.testing_files.purchase_response, __FILE__))
		else
			unless order_list.nil?
			  	begin
				  	response = RestClient.post(method_url, order_list.to_json,
				  	 	"Authorization" => configatron.lending_club.authorization,
				  	 	"Accept" => configatron.lending_club.content_type,
				  	 	"Content-Type" => configatron.lending_club.content_type
				  	 	)
				rescue
					if $verbose
						puts "Order Response:  #{response}"
						puts "order_list: #{order_list}"
					end
					PB.add_line("Failure in: #{__method__}\nUnable to place order with method_url:\n#{method_url}")
					report_order_response(nil) # order failed; enusure reporting
					return
				end
			end
		end
		report_order_response(response)
	end

	def report_order_response(response)

		unless response.nil?
				response = JSON.parse(response)
				File.open(File.expand_path(configatron.logging.order_response_log), 'a') { |file| file.write("#{Time.now.strftime("%H:%M:%S %d/%m/%Y")}\n#{response}\n\n") }
			begin
				puts "Response: #{response}"
				invested = response.values[1].select { |o| o["executionStatus"].include? 'ORDER_FULFILLED' }
				not_in_funding = response.values[1].select { |o| o["executionStatus"].include? 'NOT_AN_IN_FUNDING_LOAN' }
				PB.set_subject("#{invested.size.to_i} of #{@purchasable_loan_count}/#{[Loans.fundable_loan_count.to_i, @loan_list.size].max}")
				PB.add_line("Successfully Invested:  #{invested.inject(0) { |sum, o| sum + o["investedAmount"].to_f }}") # dollar amount invested
				if not_in_funding.any?
					PB.add_line("No longer in funding:  #{not_in_funding.size}") # NOT_AN_IN_FUNDING_LOAN
				end
			rescue
				if $verbose
					puts "Order Response:  #{response}"
				end
				PB.add_line("Failure in: #{__method__}\nUnable to report on order response.\nSee ~/Library/Logs/LC-PurchaseResponse.log for order response.")
			end
		else
			PB.set_subject "0 of #{@purchasable_loan_count}/#{[Loans.fundable_loan_count.to_i, @loan_list.size].max}"
		end
	end

end


class Account

	def available_cash
		@available_cash ||= Account.get_available_cash
	end

	def self.get_available_cash
		method_url = "#{configatron.lending_club.base_url}/#{configatron.lending_club.api_version}/accounts/#{configatron.lending_club.account}/availablecash"
		if $verbose
			puts "Pulling available cash amount."
			puts "method_url: #{__method__} -> #{method_url}"
		end

		begin 
			response = RestClient.get(method_url,
			 		"Authorization" => configatron.lending_club.authorization,
			 		"Accept" => configatron.lending_club.content_type,		
			 		"Content-Type" => configatron.lending_club.content_type
				)
			result = JSON.parse(response)['availableCash']
			PB.add_line("Available Cash:  #{result}")
		rescue
			PB.add_line("Failure in: #{__method__}\nUnable to get current account balance.")
		end
		
		return result
	end

end


class PushBullet

	def initialize
		pb_client
	end

	def pb_client
		@pb_client ||= PushBullet.initialize_push_bullet_client
		add_line(Time.now.strftime("%H:%M:%S %m/%d/%Y"))
	end

	def self.initialize_push_bullet_client
		Washbullet::Client.new(configatron.push_bullet.api_key)
	end

	def add_line(line)
		@message = "#{@message}\n#{line}"
	end
	
	def set_subject(purchase_count)
		@subject = "Lending Club AutoInvestor - #{purchase_count} purchased"
		if $debug
			@subject = "* DEBUG * " + @subject
		end
	end

	def send_message
		if $verbose
	 		puts "PushBullet Message:"
	 		puts view_message
	 	end

	 	begin 
			@pb_client.push_note(receiver: configatron.push_bullet.device_id, params: { title: @subject, body: @message } )
		rescue
			puts "Failure in: #{__method__}\nUnable to send the following PushBullet note:\n"
			puts view_message
		ensure
			#@pb_client = nil
			# setting @message and @subject to nil as setting @pb_client to nil does not appear to cause PushBullet.initialize_push_bullet_client to be called when next launched
			@message = nil
			@subject = nil
		end
	end

	def view_message
		puts "PushBullet Subject:  #{@subject}"
		puts "Message:  #{@message}"
	end

end
