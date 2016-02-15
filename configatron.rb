require 'configatron'

configatron.configure_from_hash(
	lending_club:
	{
		authorization: '', 	#Lending Club API key
		account: 12341234, 	#Lending Club account number
		portfolio_id: 12341234,  	# id of the portfolio to add purchased notes to
		investment_amount: 25, 		# amount to invest per loan ($25 minimum)

		api_version: 'v1',
		base_url: 'https://api.lendingclub.com/api/investor',
		content_type: 'application/json',
	},
	push_bullet:
	{
		api_key: '',
		device_id: '' #iphone 6S plus
	},
	logging:
	{
		#path to store log files
		order_response_log: '/var/log/lending_club_autoinvestor/lc_order_response.log',
		order_list_log: '/var/log/lending_club_autoinvestor/lc_order_list.log'
	},
	testing_files:
	{
		#alternate between the two purchase_response values to alternate test types
		purchase_response: 'test/mixed_purchase_response.json',
		#purchase_response: 'test/failed_purchase_response.json',
		available_loans: 'test/available_loans.json',
		owned_loans:  'test/owned_loans.json'
	}
)
