import requests
import json
from web3 import Web3
import os
from dotenv import load_dotenv
from multicall import Multicall, Call

#TODO: use https://book.getfoundry.sh/forge/differential-ffi-testing?highlight=ffi#primer-the-ffi-cheatcode
price_endpoint = "https://apiv5.paraswap.io/prices?"

tx_endpoint = "https://apiv5.paraswap.io/transactions/"

load_dotenv()


def init_web3():#TODO: this version only works with mainnet
    alchemy_eth_socket = os.getenv('ALCHEMY_ETH_SOCKET')
    eth_w3 = Web3(Web3.HTTPProvider(alchemy_eth_socket))
    print("Connected to EVM network with chain ID: ", eth_w3.eth.chainId)

    # Print if web3 is successfully connected
    print(eth_w3.isConnected())

    # Get the latest block number
    latest_block = eth_w3.eth.block_number
    print('latest block is ' + str(latest_block))
    return eth_w3



def create_cached_decimals(token_address_list : list[str]) -> dict[str, int]:
    cached_decimals_temp = {}
    call_list = []
    with open("./cached_decimals.txt", 'r') as file:
        cached_decimals_temp = json.load(file)
    cached_decimals_temp["0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"] = 18
    cached_decimals_temp["0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE".lower()] = 18
    for token_address in token_address_list:
        if token_address not in cached_decimals_temp.keys():
            call_list.append(Call(token_address, ['decimals()(uint)'], [[token_address, None]]))
    tokens_to_decimals_multicall = Multicall(call_list, _w3=eth_w3)()
    for token, decimals in tokens_to_decimals_multicall.items():
        cached_decimals_temp[token] = decimals
    with open("./cached_decimals.txt", 'w') as file:
        json.dump(cached_decimals_temp, file)
    return cached_decimals_temp

def build_price_query(srcToken: str, destToken: str, amount_out: int, network : int, user_address: str) -> str:
    query = "srcToken=" + srcToken + "&srcDecimals=" + str(cached_decimals[srcToken]) + "&destToken=" + destToken + "&destDecimals=" + str(cached_decimals[destToken]) + "&amount=" + str(amount_out) + "&side=BUY&network=" + str(network)
    if len(user_address) != 0:
        query += "&userAddress=" + user_address
    return query

def build_tx_query(network: int, gasPrice: int, ignoreChecks: bool, ignoreGasEstimate : bool) -> str:
    query = str(network) + "?gasPrice=" + str(gasPrice) + "&ignoreChecks=" + str(ignoreChecks).lower() + "&ignoreGasEstimate=" + str(ignoreGasEstimate).lower() + "&onlyParams=false"
    return query

def build_tx_data(tx_data: dict, user_address: str) -> str:
    tx_data["userAddress"] = user_address
    tx_data["srcToken"] = tx_data["priceRoute"]["srcToken"]
    tx_data["destToken"] = tx_data["priceRoute"]["destToken"]
    tx_data["srcAmount"] = tx_data["priceRoute"]["srcAmount"]
    tx_data["destAmount"] = tx_data["priceRoute"]["destAmount"]
    tx_data["srcDecimals"] = tx_data["priceRoute"]["srcDecimals"]
    tx_data["destDecimals"] = tx_data["priceRoute"]["destDecimals"]
    return tx_data

def query_api_get(query: str, endpoint: str) -> dict[str]:
    response = requests.get(endpoint + query)
    print('API call for the ', endpoint, ' has a response ', response)
    if response.status_code == 200:
        return json.loads(response.content)
    print(response.content)
    raise Exception('Query failed. return code is {}.     {}'.format(response.status_code, query))

def query_api_post(query: str, endpoint: str, data: dict) -> dict[str]:
    print(endpoint+query)
    response = requests.post(endpoint + query, json = data)
    print('API call for the ', endpoint, ' has a response ', response)
    if response.status_code == 200:
        return json.loads(response.content)
    print(response.content)
    raise Exception('Query failed. return code is {}.     {}'.format(response.status_code, query))


def get_tx_data(src_token: str, dest_token: str, amount_out: int, network: int, gasPrice: int, user_address: str) -> str:
    price_query = build_price_query(src_token, dest_token, amount_out, network, user_address)
    price_api_response = query_api_get(price_query, price_endpoint)
    tx_query = build_tx_query(network, gasPrice, True, True)
    tx_data = build_tx_data(price_api_response, user_address)
    tx_api_reponse = query_api_post(tx_query, tx_endpoint, tx_data)
    print(tx_api_reponse)

eth_w3 = init_web3()
cached_decimals = create_cached_decimals(["0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"])
get_tx_data("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 1000000000, 1, 50000000000, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
