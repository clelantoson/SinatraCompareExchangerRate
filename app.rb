# app.rb

require 'sinatra'
require "sinatra/reloader" if development?
require 'httparty'
require 'json'
require 'pry'
require 'tzinfo'
require 'sinatra/cors'

set :allow_origin, "http://localhost:8081" # Allow your frontend
set :allow_methods, "GET"    # Define which methods are allowed
set :allow_headers, "content-type"        # Specify allowed headers

CURRENCIES_WITH_CENTS = [
  "USD", # United States Dollar
  "CAD", # Canadian Dollar
  "AUD", # Australian Dollar
  "NZD", # New Zealand Dollar
  "SGD", # Singapore Dollar
  "HKD", # Hong Kong Dollar
  "EUR", # Euro
  "GBP", # British Pound Sterling
  "ZAR", # South African Rand
  "MXN", # Mexican Peso
  "ARS", # Argentine Peso
  "CLP", # Chilean Peso
  "COP", # Colombian Peso
  "PEN", # Peruvian Sol
  "CNY", # Chinese Yuan
  "INR", # Indian Rupee
  "PHP", # Philippine Peso
  "MYR", # Malaysian Ringgit
  "THB", # Thai Baht
  "TWD"  # Taiwan Dollar
].freeze

CURRENCIES_WITHOUT_COMPUTING = [
  "BRL", # Brazilian Real
]


# mastercard
def get_current_cst_time
    tz_cst = TZInfo::Timezone.get('America/Chicago')
    tz_cst.now
end

def current_time_after_12_hours_cst?
  current_time_cst = get_current_cst_time
  current_time_cst.hour >= 12
end

def correct_date_for_mastercard
  current_time_cst =  get_current_cst_time

  if current_time_after_12_hours_cst?
    current_time_cst.strftime('%Y-%m-%d') # Date du jour
  else
    (current_time_cst - 1).strftime('%Y-%m-%d') # Date d'hier
  end
end

# visa
def current_time_after_midnight_utc?
  current_time_utc = Time.now.utc
  current_time_utc.hour >= 0
end

def correct_date_for_visa
  current_time_utc = Time.now.utc

  if current_time_after_midnight_utc?
    current_time_utc.strftime('%m-%d-%Y').gsub('-', '%2F') # today date
  else
    (current_time_utc - 1).strftime('%m-%d-%Y').gsub('-', '%2F') # yesterday date
  end
end

def format_amount_revolut(amount)
  amount.to_i
end

def format_and_combine_results(visa_result, mastercard_result, revolut_result, to_currency, from_currency, amount)
  visa_conversion_rate = visa_result['originalValues']['fxRateVisa'].to_f
  visa_converted_amount = visa_result['originalValues']['toAmountWithAdditionalFee'].to_f

  mastercard_conversion_rate = mastercard_result['data']['conversionRate']
  mastercard_converted_amount = mastercard_result['data']['crdhldBillAmt']

  revolut_conversion_rate = revolut_result['rate']['rate']

  revolut_converted_amount = revolut_conversion_rate.to_f * format_amount_revolut(amount)

  {
    visa: {
      conversion_rate: visa_conversion_rate.round(2),
      conversion_rate_inverse: (1 / visa_conversion_rate).round(2),
      converted_amount: visa_converted_amount.round(2),
    },
    mastercard: {
      conversion_rate: mastercard_conversion_rate.round(2),
      conversion_rate_inverse: (1 / visa_conversion_rate).round(2),
      converted_amount: mastercard_converted_amount.round(2),
    },
    revolut: {
      conversion_rate: revolut_conversion_rate.round(2),
      conversion_rate_inverse: (1 / visa_conversion_rate).round(2),
      converted_amount: revolut_converted_amount.round(2),
    },
       from_currency: from_currency,
       to_currency: to_currency,
  }
end

get '/get_exchange_rate' do
  content_type :json

  from_currency = params[:from_currency]
  to_currency = params[:to_currency]
  amount = params[:amount]

  revolut_response = HTTParty.get("https://www.revolut.com/api/exchange/quote?",
    query: {
      isRecipientAmount: false,
      fromCurrency: from_currency,
      toCurrency: to_currency,
      amount:format_amount_revolut(amount),
      country: "FR",
    },
    headers: {
      "accept-language": "fr",
    }
  )


  visa_response = HTTParty.get("https://www.visa.fr/cmsapi/fx/rates?utcConvertedDate=#{correct_date_for_visa}&exchangedate=#{correct_date_for_visa}",
    query: {
      fromCurr: to_currency,
      toCurr: from_currency,
      amount: amount,
      fee: 0,
    },
    headers: {
      referer: 'https://www.visa.fr/aide-visa/consommateur/services-de-voyage-visa/exchange-rate-calculator.html',
    }
  )


  mastercard_response = HTTParty.get("https://www.mastercard.fr/settlement/currencyrate/conversion-rate?",
    query: {
      fxDate: correct_date_for_mastercard,
      transCurr: from_currency,
      crdhldBillCurr: to_currency,
      transAmt: amount,
      bankFee: 0,
    },
    headers: {
    }
  )



  if visa_response.success? && mastercard_response.success? && revolut_response.success?
    visa_result = JSON.parse(visa_response.body)
    mastercard_result = JSON.parse(mastercard_response.body)
    revolut_result = JSON.parse(revolut_response.body)

    combined_result = format_and_combine_results(visa_result, mastercard_result, revolut_result, to_currency, from_currency, amount)

    return combined_result.to_json


  elsif !visa_response.success?
    status 500
    return { error: "Erreur lors de la récupération des taux de change de Visa" }.to_json

  elsif !mastercard_response.success?
    status 500
    return { error: "Erreur lors de la récupération des taux de change de Mastercard" }.to_json

  elsif !revolut_response.success?
    binding.pry
    status 500
    return { error: "Erreur lors de la récupération des taux de change de Revolut" }.to_json
  end

end


