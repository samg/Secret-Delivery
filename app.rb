require 'rubygems'
require 'sinatra'
require 'haml'
require 'actionmailer'

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

get '/' do
  keys = `gpg --list-keys`
  haml :form, :locals => {:keys => keys.grep(/uid/).map{|s| s.gsub(/uid\s*/, '')}}
end

post '/deliver' do
  # validation
  if params[:to].blank? or params[:secrets].blank?
    haml '%h3 Please specify recipient and secrets'
  else
    # reject blank params
    params.each { |k,v| params.delete(k) if v.blank? }

    io = IO.popen("gpg -e --trust-model always -r '#{params['to']}'", "r+")
    io.puts params[:secrets]
    io.close_write
    to = params['to'].match(/<(.*)>/)[1] #extract email address
    ApplicationMailer.deliver_secret(params['to'], params[:cleartext], params[:filename] , io)
    io.close_read
    redirect "/success/#{to}"
  end
end

get '/success/:to' do
  haml "%h1 Success\n%p Your secrets have been transmitted to #{params[:to].inspect}\n%p\n  %a{:href => '/'} Again"
end

get '/import' do
  haml :import_form
end

post '/import' do
  unless params[:keyid].to_s == ""
    system 'gpg', '--recv-keys', params[:keyid]
  end
  unless params[:pubkey].to_s == ""
    IO.popen('gpg --import', 'w'){|io| io.puts params[:pubkey]}
  end
  redirect '/'
end

ActionMailer::Base.delivery_method = :sendmail
class ApplicationMailer < ActionMailer::Base
  def secret(to, cleartext, filename, io)
    recipients      to
    subject         "Secrets"
    from            "secrets@#{`hostname`}"
    body            [
      "someone has sent you some secrets",
      "Use gpg key #{to.inspect} to decrypt it",
      "\n",
      "This clear text message was written for you by the sender of this message",
      "========================================",
      cleartext
    ].join("\n")

    attachment "application/pgp-encrypted" do |a|
      a.filename = filename + '.gpg' || "secrets.#{Time.now.to_i}.gpg"
      a.body = io.inject{|m,s| m << s}
    end
  end
end



template :layout do
  <<-HAML
!!! Strict
%html{html_attrs('en-en')}
  %head
    %meta{'http-equiv' => "content-type", :content => "text/html; charset=utf-8"}
    %title Secret Delivery
    %style{:type => 'text/css'}
      textarea{width:100%;height:15em;border:solid 1px #666;}
      textarea:focus{background:#ffe;border:solid 1px #666;}
  %body
    #container.container_12
      #header
        %h1 Secret Delivery
      #wrapper
        #flash
        #content= yield
  HAML
end

template :form do
  <<-HAML
%ol
  %li Text is transferred from your browser over an encrypted connection (if it says https in your address bar)
  %li On the server the text is encrypted using the recipient's public pgp key (so only they can decrypt it)
  %li The encrypted data is emailed to the recipient
%p
  For questions about this app email Sam Goldstein at
  %a{:href => 'mailto:sgrock@gmail.com'} sgrock@gmail.com
%form{:method => 'post', :action => '/deliver'}
  %p
    %label{:for => 'to'}
      Deliver To:
    %select{:id => 'to', :name => 'to'}
      -keys.unshift('').each do |k|
        %option{:value => k}
          = h k
    (
    %a{:href => '/import'} Import another key
    )
  %p
    %label{:style => 'color:blue;', :for => 'secrets'} Secrets (encrypted):
    %textarea{:style => 'border:1px solid blue;', :name => 'secrets'}
  %p
    %label{:style => 'color:red;', :for => 'email'} Email Text (optional - not encrypted):
    %textarea{:style => 'border: solid 1px red;', :name => 'cleartext'}
  %p
    %label{:style => 'color:red;', :for => 'email'} Filename for Encrypted Secrets (optional - not encrypted):
    %input{:style => 'border: 1px solid red;', :type => 'text', :name => 'filename'}
  %p
    %input{:type => 'submit', :value => 'Send Secrets'}
  HAML
end

template :import_form do
  <<-HAML
%form{:method => 'post', :action => '/import'}
  %p{:style => 'font-weight:bold'}
    Find your key on a keyserver such as
    %a{:href => 'http://pgp.mit.edu:11371/'} http://pgp.mit.edu:11371/
  %p{:style => 'font-weight:bold'}
    Find its id (it will look something like "5B8CD968")
  %p{:style => 'font-weight:bold'}
    Paste that id into this form
  %p
    %label{:for => 'keyid'} Key Id:
    %input{:type => 'text', :name => 'keyid'}
  %p
    %strong OR
    paste your ascii armored public key into the text field below
  %p
    %label{:for => 'pubkey'} 
    %textarea{:name => 'pubkey'}
  %p
    %input{:type => 'submit', :value => 'Import Key'}
  %p
    %pre
      = h `gpg --list-keys`
  HAML
end



