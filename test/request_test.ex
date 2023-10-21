defmdoule Request do
  use ExUnit.Case
  doctest Ipncore
  import Builder, only: [post: 2]

  test "" do
    hostname = "visurpay.com"
    {c1, c2} = Builder.test()
    {:ok, c2} = Builder.wallet_sub(c2, vid) |> post(hostname)


  end
end
