require 'test_helper'

class RemoteOpenpayTest < Test::Unit::TestCase
  def setup
    @gateway = OpenpayGateway.new(fixtures(:openpay))

    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @store_card = credit_card('5105105105105100')
    @declined_card = credit_card('4222222222222220')

    @options = {
      billing_address: address,
      description: 'Store Purchase',
      email: "me@email.com"
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message
  end

  def test_successful_purchase_merchant_account_id
    @options[:merchant_account_id] = "msbt1ra6v1oe8wsymskg"
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message
  end

  def test_successful_purchase_dollar
    @options[:currency] = "usd"
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message
    assert_not_nil response.params
    assert_equal "USD", response.params["currency"]
  end

  def test_successful_purchase_with_metadada
    @options[:metadata] = {
      one_field: "value one",
      second_field: "value second"
    }
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message
    assert_not_nil response.params
    assert_not_nil response.params["metadata"]
  end

  def test_successful_purchase_with_customer
    @options[:customer] = {
      external_id: SecureRandom.hex, #It must be unique
      name: "customer name",
      last_name: "customer lastname",
      phone_number: "+521234567890"
    }
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message
    assert_not_nil response.params
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 3001, response.params['error_code'] #The card was decline
  end

  def test_successful_refund
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message

    assert response = @gateway.refund(@amount, response.authorization, @options)
    assert_success response
    assert_nil response.message
    assert response.params['refund']
    assert_equal 'completed', response.params['status']
    assert_equal 'completed', response.params['refund']['status']
  end

  def test_unsuccessful_refund
    assert response = @gateway.refund(@amount, '1',  @options)
    assert_failure response
    assert_not_nil response.message
  end

  def test_successful_authorize
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message
  end

  def test_unsuccessful_authorize
    assert response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 3001, response.params['error_code'] #The card was decline
  end

  def test_successful_capture
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message

    assert response = @gateway.capture(@amount, response.authorization, @options)
    assert_success response
    assert_nil response.message
  end

  def test_unsuccessful_capture
    assert response = @gateway.capture(@amount, '1')
    assert_failure response
    assert_equal 'The requested resource doesn\'t exist', response.message
  end

  def test_successful_void
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_nil response.message

    assert response = @gateway.void(response.authorization, @options)
    assert_success response
    assert_equal 'cancelled', response.params['status']
  end

  def test_successful_purchase_with_card_stored
    @options[:email] = '%d@example.org' % Time.now
    @options[:name] = 'Customer name'
    response_store = @gateway.store(@store_card, @options)
    assert_success response_store
    assert_instance_of MultiResponse, response_store

    customer_stored = response_store.responses[0]
    card_stored = response_store.responses[1]
    @options[:customer] = {
      id: customer_stored.authorization
    }
    assert response = @gateway.purchase(@amount, card_stored.authorization, @options)
    assert_success response
    assert_nil response.message

    assert_success @gateway.unstore(customer_stored.authorization, card_stored.authorization)
  end

  def test_successful_purchase_with_device_session_id
    assert response = @gateway.purchase(@amount, @credit_card, @options.merge(device_session_id: 'weur2ty732yu2y47824u23yu4i'))
    assert_success response
  end

  def test_successful_store
    new_email_address = '%d@example.org' % Time.now
    assert response = @gateway.store(@credit_card, name: 'Test User', email: new_email_address)
    assert_success response
    assert_instance_of MultiResponse, response
    assert response.authorization

    @options[:customer] = {
      id: response.authorization
    }
    assert second_card = @gateway.store(@store_card, @options)
    assert_success second_card
    assert_instance_of Response, second_card
    assert second_card.authorization

    customer_stored = response.responses[0]
    first_card = response.responses[1]

    assert_success @gateway.unstore(customer_stored.authorization, first_card.authorization)
    assert_success @gateway.unstore(customer_stored.authorization, second_card.authorization)
    assert_success @gateway.unstore(customer_stored.authorization)
  end

  def test_invalid_login
    gateway = OpenpayGateway.new(
      key: '123456789',
      merchant_id: 'mwfxtxcoom7dh47pcds1',
      production: true
    )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'The api key or merchant id are invalid', response.message
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    clean_transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, clean_transcript)
    assert_scrubbed(@credit_card.verification_value.to_s, clean_transcript)
  end
end
