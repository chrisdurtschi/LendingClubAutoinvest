require 'configatron'

configatron.configure_from_hash(
	lending_club:
	{
		authorization: '',
		account: 11111111,
		portfolio_id: 22222222,  	
		investment_amount: 25, 		# amount to invest per loan ($25 minimum)

		api_version: 'v1',
		base_url: 'https://api.lendingclub.com/api/investor',
		content_type: 'application/json',
	},
	push_bullet:
	{
		api_key: '',
		device_id: ''
	},
	logging:
	{
		order_response_log: '~/Library/Logs/LC-OrderResponse.log'
	},
	testing_files:
	{
		purchase_response: 'Test/PurchaseResponse.rb',
		available_loans: 'Test/AvailableLoans.rb',
		owned_loans:  'Test/OwnedLoans.rb'
	}
)
