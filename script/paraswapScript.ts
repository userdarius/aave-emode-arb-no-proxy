        // on veut utiliser l'API de paraswap pour avoir au moins amountTolashloan en longToken après le swap en vendant du shortToken
        // prendre en compte le premium du flashloan
        //ou prendre une marge de 1% pour le slippage et le premium
        //uint256 amountToFlashLoan = _amountDeposited * (_leverageRatio - 1);
        //TODO: utiliser l'API de paraswap 1 fois pour récuperer la donné du swap
        //puis script foundry qui va donner ça en argument