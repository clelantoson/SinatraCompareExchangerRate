# app.rb

require 'sinatra'
require "sinatra/reloader" if development?
require 'httparty'
require 'json'
require 'pry'
require 'tzinfo'

get '/get_exchange_rate' do
  content_type :json

  from_currency = params[:from_currency]
  to_currency = params[:to_currency]
  amount = params[:amount]


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
    current_time_utc.strftime('%m-%d-%Y').gsub('-', '%2F') # Date du jour
  else
    (current_time_utc - 1).strftime('%m-%d-%Y').gsub('-', '%2F') # Date d'hier
  end
end


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





 # Vérifier si les deux réponses sont réussies
  if visa_response.success? && mastercard_response.success?
    visa_result = JSON.parse(visa_response.body)
    mastercard_result = JSON.parse(mastercard_response.body)

    # Combiner les résultats dans un seul objet
    combined_result = {
      visa: {
        conversion_rate: visa_result['originalValues']['fxRateVisa'],
        converted_amount: visa_result['originalValues']['toAmountWithAdditionalFee']
      },
      mastercard: {
        conversion_rate: mastercard_result['data']['conversionRate'],
        converted_amount: mastercard_result['data']['crdhldBillAmt']
      }
    }

    return combined_result.to_json

  # Gérer les erreurs pour Visa
  elsif !visa_response.success?
    status 500
    return { error: "Erreur lors de la récupération des taux de change de Visa" }.to_json

  # Gérer les erreurs pour Mastercard
  elsif !mastercard_response.success?
    status 500
    return { error: "Erreur lors de la récupération des taux de change de Mastercard" }.to_json
  end
end



# visa
# https://www.visa.fr/cmsapi/fx/rates?amount=1000&fee=0&utcConvertedDate=09%2F18%2F2024&exchangedate=09%2F18%2F2024&fromCurr=EUR&toCurr=JPY

# revolut
# https://www.revolut.com/api/exchange/quote?amount=100000&country=FR&fromCurrency=JPY&isRecipientAmount=false&toCurrency=EUR
