require 'configatron'

configatron.configure_from_hash(
	lending_club:
	{
		authorization: '', #API key
		account: 2628791, #Lending Club account number
		portfolio_id: 59612258,  	# id of the portfolio to add purchased notes to
		investment_amount: 25, 		# amount to invest per loan ($25 minimum)

		api_version: 'v1',
		base_url: 'https://api.lendingclub.com/api/investor',
		content_type: 'application/json',
	},
	push_bullet:
	{
		api_key: '',
		device_id: '' #iphone 5s
	},
	logging:
	{
		#relative paths for OSX logging
		order_response_log: '~/Library/Logs/LC-OrderResponse.log',
		order_list_log: '~/Library/Logs/LC-OrderList.log'
	},
	testing_files:
	{
		#alternate between the two purchase_response values alternate test types
		purchase_response: 'Test/MixedPurchaseResponse.rb',
		#purchase_response: 'Test/FailedPurchaseResponse.rb',
		available_loans: 'Test/AvailableLoans.rb',
		owned_loans:  'Test/OwnedLoans.rb'
	}
)
