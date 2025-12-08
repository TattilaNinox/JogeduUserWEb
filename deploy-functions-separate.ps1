# Firebase Functions külön-külön deploy parancsok PowerShell-ben
# Használat: Futtasd le ezeket a parancsokat egyenként, vagy válaszd ki, melyiket szeretnéd futtatni

Write-Host "=== Firebase Functions Deploy Parancsok ===" -ForegroundColor Cyan
Write-Host ""

# 1. Eszközváltás funkciók
Write-Host "1. Eszközváltás funkciók:" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions:requestDeviceChange,functions:verifyAndChangeDevice" -ForegroundColor Green
Write-Host ""

# 2. Webes fizetési funkciók
Write-Host "2. Webes fizetési funkciók:" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions:initiateWebPayment,functions:confirmWebPayment,functions:updatePaymentStatusFromCallback,functions:processWebPaymentWebhook,functions:simplepayWebhook" -ForegroundColor Green
Write-Host ""

# 3. Fizetési trigger és scheduled funkciók
Write-Host "3. Fizetési trigger és scheduled funkciók:" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions:onWebPaymentWrite,functions:reconcileWebPaymentsScheduled" -ForegroundColor Green
Write-Host ""

# 4. Előfizetési emlékeztető funkciók
Write-Host "4. Előfizetési emlékeztető funkciók:" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions:sendSubscriptionReminder,functions:checkSubscriptionExpiry,functions:checkSubscriptionExpiryScheduled,functions:checkTrialExpiryScheduled" -ForegroundColor Green
Write-Host ""

# 5. Admin és cleanup funkciók
Write-Host "5. Admin és cleanup funkciók:" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions:adminCleanupUserTokensBatch,functions:adminCleanupUserTokensHttp,functions:cleanupOldTokens,functions:cleanupUserTokens" -ForegroundColor Green
Write-Host ""

# 6. Egyéb funkciók
Write-Host "6. Egyéb funkciók:" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions:fixExpiredSubscriptions,functions:reconcileSubscriptions,functions:handlePlayRtdn" -ForegroundColor Green
Write-Host ""

# 7. TELJES FUNCTIONS DEPLOY (minden funkció egyszerre - BIZTONSÁGOS, mert minden funkció benne van az index.js-ben)
Write-Host "7. TELJES FUNCTIONS DEPLOY (ajánlott):" -ForegroundColor Yellow
Write-Host "firebase deploy --only functions" -ForegroundColor Green
Write-Host ""

Write-Host "=== VÁLASZTÁS ===" -ForegroundColor Cyan
Write-Host "A 7. opció (teljes deploy) a legegyszerűbb és biztonságos, mert minden funkció benne van az index.js-ben." -ForegroundColor White
Write-Host "A BOM karakterek javítása miatt csak az index.js fájl változott, így a teljes deploy biztonságos." -ForegroundColor White



