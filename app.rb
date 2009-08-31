require 'rubygems'
require 'sinatra'
require 'haml'
require 'actionmailer'

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
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
  %li Text is transferred from your browser over an encrypted connection
  %li On the server the text is encrypted using the recipient's public pgp key (so only they can decrypt it)
  %li The encrypted data is emailed to the recipient
%form{:method => 'post', :action => '/deliver'}
  %p
    %label{:for => 'to'} Deliver To:
    %select{:id => 'to', :name => 'to'}
      -keys.unshift('').each do |k|
        %option{:value => k}
          = h k
  %p
    %label{:for => 'secrets'} Secrets:
    %textarea{:name => 'secrets'}
  %p
    %input{:type => 'submit', :value => 'Send Secrets'}
  HAML
end

get '/' do
  keys = `gpg --list-keys`
  haml :form, :locals => {:keys => keys.grep(/uid/).map{|s| s.gsub(/uid\s*/, '')}}
end

post '/deliver' do
  if params[:to].blank? or params[:secrets].blank?
    haml '%h3 Please specify recipient and secrets'
  else 
    io = IO.popen("gpg -er '#{params['to']}'", "r+")
    io.puts params[:secrets]
    io.close_write
    to = params['to'].match(/<(.*)>/)[1] #extract email address
    ApplicationMailer.deliver_secret(params['to'], io)
    io.close_read
    redirect "/success/#{to}"
  end
end

get '/success/:to' do
  haml "%h1 Success\n%p Your secrets have been transmitted to #{params[:to].inspect}\n%p\n  %a{:href => '/'} Again"
end

ActionMailer::Base.delivery_method = :sendmail
class ApplicationMailer < ActionMailer::Base
  def secret(to, io)
    recipients      to
    subject         "Secrets"
    from            "secrets@drasticcode.com"
    body            "someone has sent you some secrets"

    attachment "application/pgp-encrypted" do |a|
      a.filename = "secrets.#{Time.now.to_i}.gpg"
      a.body = io.inject{|m,s| m << s}
    end
  end
end

