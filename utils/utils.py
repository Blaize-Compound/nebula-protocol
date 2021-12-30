
def amount_in_small_dimension(amount, token_instance):
    return int(10 ** token_instance.decimals() * amount)