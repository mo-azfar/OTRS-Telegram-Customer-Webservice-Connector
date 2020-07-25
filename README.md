# OTRS-Telegram-Customer-Webservice-Connector   
- Built for OTRS CE v6.0  
- This module enable the integration from Telegram users (customer/public) to OTRS.  
- by conversation with a bot, customer or public can get create a ticket and search a ticket submitted by him/her.  

- **STATUS: Work In Progress .(Refer Project).**

		Used CPAN Modules:
		
		MIME::Base64();
		Net::CIDR::Set;
		JSON::MaybeXS;
		LWP::UserAgent;
		HTTP::Request::Common;
		Encode qw(decode encode);
		Digest::MD5 qw(md5_hex);
		Date::Parse;
		Data::Dumper;

1. Create a telegram bot and get a bot token  

2. Update telegram webhook to point to otrs REST Webservices  
    
    	https://api.telegram.org/bot<BOT_TOKEN>/setWebhook?url=https://<SERVERNAME>/otrs/nph-genericinterface.pl/Webservice/GenericTicketConnectorREST/TicketTelegramCustomer/?UserLogin=webservice;Password=432655otrs

 
3. As per url, its point to /TicketTelegramCustomer/ connector with user and password assign to them. webservice user should at least have write permision.  

  
4. In OTRS, Go to Webservice (REST), Add operation TelegramCustomer::TicketTelegramCustomer  

		Name: TicketTelegramCustomer


5. Configure REST Network Trasnport  

  		*Route mapping for Operation 'TicketTelegramCustomer': /TicketTelegramCustomer/  
  		*Method: POST  

6. Create Customer User DynamicField and enable mapping field at CustomerUser Config.  
	
		Name: ICPassport
		Object: Customer User
		Type: Text

7. Create Ticket DynamicField.  
	
		Name: TicketICPassport
		Object: Ticket
		Type: Text


8. Enable mapping for customer user profile to ticket dynamic field at System Configuration  

		- Ticket::EventModulePost###4100-DynamicFieldFromCustomerUser  
		- DynamicFieldFromCustomerUser::Mapping  
			- DynamicField_ICPassport => TicketICPassport  
	
	

9. Update System Configuration > GenericInterface::Operation::TicketTelegramCustomer###CustomerVerification  

  		*field that hold the customer profile verification (unique) value. Default: DynamicField_ICPassport  
		*purpose: to search customer user based on this dynamicf field (customer) and value.


10. Update System Configuration > GenericInterface::Operation::TicketTelegramCustomer###TicketVerification  

		*field that hold the ticket verification (unique) value. Default: DynamicField_TicketICPassport
		*purpose : to search ticket based on this dynamic field (ticket) and value.
	
	
11. Update System Configuration > GenericInterface::Operation::TicketTelegramCustomer###Token  

  		Update the token (get from no 1).  


12. May be good idea to create a QR code for customer or public to allow direct access to the bot.

		https://t.me/<bot_username>


13. Rules check

		- For registered customer, IC Number or Passport Number should be present in their profile (DynamicField_ICPassport).  
		- The unique key to search for the Ticket is IC Number or Passport Number.
		- So, each created ticket must have this IC Number or Passport Number tag to the ticket (DynamicField_TicketICPassport).
		- Only ip address from telegram server are allowed to use this connector.


11. To test the connection to telegram,

		shell > curl -X GET https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getMe   


SIMULATION:

[![1.png](https://i.postimg.cc/VLPSthx1/1.png)](https://postimg.cc/0rZ2RV5H)  

[![2.png](https://i.postimg.cc/sgVv6hfN/2.png)](https://postimg.cc/rKPVzzr1)  

[![3.png](https://i.postimg.cc/1353c1Jx/3.png)](https://postimg.cc/6ygKtSkz)  

[![3.jpg](https://i.postimg.cc/zBjSgMzZ/3.jpg)](https://postimg.cc/DJSXVx4B)  

	

