require 'configatron'

configatron.configure_from_hash(
	lending_club:
	{
		authorization: 'XjVzPbmT55/TX7k6t5Uzwv2yT2M=',
		account: 2628791,
		portfolio_id: 59612258,  	# "Autoinvestor"
		investment_amount: 25, 		# amount to invest per loan ($25 minimum)

		api_version: 'v1',
		base_url: 'https://api.lendingclub.com/api/investor',
		content_type: 'application/json',
	},
	push_bullet:
	{
		api_key: 'M1MzGV2ynrIBCGWKvd9ReeAuJVK765Gc',
		device_id: 'ujweNd5igMesjAiVsKnSTs' #iphone 5s
	}
)
