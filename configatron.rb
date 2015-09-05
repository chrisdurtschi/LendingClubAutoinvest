configatron.configure_from_hash(
	lending_club:
	{
		authorization: '',
		account: 999999999,
		portfolio_id: 999999999,
		investment_amount: 00, 		# amount to invest per loan ($25 minimum)

		api_version: 'v1',
		base_url: 'https://api.lendingclub.com/api/investor',
		content_type: 'application/json',
	},
	push_bullet:
	{
		api_key: '',
		device_id: ''
	}
)
