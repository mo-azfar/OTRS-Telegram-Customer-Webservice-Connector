# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::TelegramCustomer::Common;

use strict;
use warnings;

use MIME::Base64();
use Net::CIDR::Set;
use JSON::MaybeXS;
use LWP::UserAgent;
use HTTP::Request::Common;

use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub ValidateTelegramIP {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{REMOTE_ADDR};
        
    my $TelegramServer = Net::CIDR::Set->new( '149.154.160.0/20', '91.108.4.0/22' );
    my $AllowedServer;
    
    if ( $TelegramServer->contains( $Param{REMOTE_ADDR} ) ) 
    {
    $AllowedServer = $Param{REMOTE_ADDR};
    return $AllowedServer;
    }
    else 
    {
	return;
    }
    
} 

sub ValidateCache {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{Type};
    return if !$Param{Key};
    
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    
    #get cache    
    my $Result = $CacheObject->Get(
        Type => $Param{Type},
        Key  => $Param{Key},
    );
        
    return $Result;
    
} 

sub ValidateTelegramCustomer {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{Customer};

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
    my $CustomerVerificationField = $ConfigObject->Get('GenericInterface::Operation::TicketTelegramCustomer')->{'CustomerVerification'};
    
    my $CustomerUserIDsRef = $CustomerUserObject->CustomerSearchDetail(
		# all search fields possible which are defined in CustomerUser::EnhancedSearchFields
        $CustomerVerificationField => 
        {
            Equals  =>  $Param{Customer},
        },
        Result => 'ARRAY',                                  # (optional)
        # default: ARRAY, returns an array of change ids
        # COUNT returns a scalar with the number of found changes
        Limit => 1,                                                  # (optional)
        # ignored if the result type is 'COUNT'
    );
	
    my $CustomerUserID;
    my $Fullname;
    
    if (!@{$CustomerUserIDsRef})
    {
        $CustomerUserID="N/A";
        $Fullname="N/A";
    }
    else
    {
        $CustomerUserID = join( ',', @{$CustomerUserIDsRef} );
        my %CustomerUser = $CustomerUserObject->CustomerUserDataGet(
            User => $CustomerUserID,
        );
        $Fullname = "$CustomerUser{UserFullname}";
        
    }
	
    my $Profile = "<pre>IC / Passport: $Param{Customer}\nRegistered ID: $CustomerUserID\nRegistered Name: $Fullname</pre>";
    return ($Profile, $CustomerUserID);
    
} 

sub CheckMyTicket {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config'); 
    my $TicketVerificationField = $ConfigObject->Get('GenericInterface::Operation::TicketTelegramCustomer')->{'TicketVerification'}; 
    
    # check needed stuff
    return if !$Param{SearchValue};
    return if !$Param{Condition};
    
    my @TicketIDs = $TicketObject->TicketSearch(
        Result => 'ARRAY',
        StateType    => \@{$Param{Condition}},
        $TicketVerificationField => {
            Empty             => 0,                       # will return dynamic fields without a value
                                                          # set to 0 to search fields with a value present
            Equals            => $Param{SearchValue},
        },
        UserID => 1,
    );
    
    my $TicketText;
    #use for telegram dynamic keyboard
    my @TicketData = ();
    
    if (@TicketIDs)
    {
        $TicketText = "Ticket Submitted By You: \n";
        foreach my $CheckTicketID (@TicketIDs)
        {
            my %CheckTicket = $TicketObject->TicketGet(
            TicketID      => $CheckTicketID,
            DynamicFields => 0,         
            UserID        => 1,
            Silent        => 0,         
            );
    
             #use for telegram dynamic keyboard
            push @TicketData, [{ 
				text => "Ticket#$CheckTicket{TicketNumber} - $CheckTicket{State}", 
				callback_data => "/get/$CheckTicketID",
			}];
        }
    }
    else
    {
        $TicketText = "No Ticket Submitted By You";
    }
    
    return ($TicketText, @TicketData);
    
} 

sub GetTicket {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{TicketID};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
    
    #permission check
    #my %NoAccess;
    #my $Access = $TicketObject->TicketPermission(
    #    Type     => 'ro',
    #    TicketID => $Param{TicketID},
    #    UserID   => $Param{UserID},
    #);
    #    
    #if ( !$Access ) 
    #{
    #        $NoAccess{GetText} = "Error: Need RO Permissions";
    #        $NoAccess{TicketURL} = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID=0';
    #        $NoAccess{TicketNumber} = "No Permission";
    #        return %NoAccess;
    #
    #}
    
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 1,         
        UserID        => 1,
        Silent        => 0,         
    );
    
    my %OwnerName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Ticket{OwnerID},
    );
    
    my %RespName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Ticket{ResponsibleID},
    );
    
    my $GetText = "
<pre>- Ticket Number: $Ticket{TicketNumber}
- Type: $Ticket{Type}
- Created: $Ticket{Created}
- State: $Ticket{State} 
- Queue: $Ticket{Queue}
- Owner: $OwnerName{UserFullname}
- Resposible: $RespName{UserFullname}
- Priority: $Ticket{Priority}
- Service: $Ticket{Service}
- SLA: $Ticket{SLA}
- Status: $Ticket{DynamicField_Status}</pre>";

    return $GetText;
    
} 

sub SentMessage {
    
    my ( $Self, %Param ) = @_;
    
    # check needed stuff
    return if !$Param{Text};
    return if !$Param{ChatID};
    return if !$Param{MsgID};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Token = $ConfigObject->Get('GenericInterface::Operation::TicketTelegramCustomer')->{'Token'};
    
    my $ua = LWP::UserAgent->new;
    my $p = {
            chat_id => $Param{ChatID},
            parse_mode => 'HTML',
            #reply_to_message_id => $Param{MsgID},
            text => $Param{Text}, 
            reply_markup => {
				#resize_keyboard => \1, # \1 = true when JSONified, \0 = false
                inline_keyboard => \@{$Param{Keyboard}}, #telegram dynamic keyboard
                force_reply => $Param{Force},
                selective => $Param{Selective}
				}
            };
            
    my $response = $ua->request(
        POST "https://api.telegram.org/bot".$Token."/sendMessage",
        Content_Type    => 'application/json',
        Content         => JSON::MaybeXS::encode_json($p)
        );
        
    my $ResponseData = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
        Data => $response->decoded_content,
    );
    
    my $msg;
    if ($ResponseData->{ok} eq 0)
    {
        $msg= "Telegram notification to $Param{ChatID}: $ResponseData->{description}",
        
    }
    else
    {
        $msg="Sent Telegram to $Param{ChatID}: $Param{Text}";
    }
    
    return $msg;
    
}

1;
