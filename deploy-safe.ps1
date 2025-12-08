# Biztonságos Firebase Functions deploy - csak azokat deployolja, amelyek az index.js-ben vannak
# Ez NEM törli a más projektekben használt funkciókat

Write-Host "=== Biztonságos Functions Deploy ===" -ForegroundColor Cyan
Write-Host "Csak az index.js-ben lévő funkciók kerülnek deployolásra" -ForegroundColor Yellow
Write-Host ""

# Egyenkénti deploy - minden funkció külön
Write-Host "1. requestDeviceChange" -ForegroundColor Green
firebase deploy --only functions:requestDeviceChange

Write-Host "`n2. verifyAndChangeDevice" -ForegroundColor Green
firebase deploy --only functions:verifyAndChangeDevice

Write-Host "`n3. initiateWebPayment" -ForegroundColor Green
firebase deploy --only functions:initiateWebPayment

Write-Host "`n4. confirmWebPayment" -ForegroundColor Green
firebase deploy --only functions:confirmWebPayment

Write-Host "`n5. updatePaymentStatusFromCallback" -ForegroundColor Green
firebase deploy --only functions:updatePaymentStatusFromCallback

Write-Host "`n6. processWebPaymentWebhook" -ForegroundColor Green
firebase deploy --only functions:processWebPaymentWebhook

Write-Host "`n7. simplepayWebhook" -ForegroundColor Green
firebase deploy --only functions:simplepayWebhook

Write-Host "`n8. onWebPaymentWrite" -ForegroundColor Green
firebase deploy --only functions:onWebPaymentWrite

Write-Host "`n9. reconcileWebPaymentsScheduled" -ForegroundColor Green
firebase deploy --only functions:reconcileWebPaymentsScheduled

Write-Host "`n10. sendSubscriptionReminder" -ForegroundColor Green
firebase deploy --only functions:sendSubscriptionReminder

Write-Host "`n11. checkSubscriptionExpiry" -ForegroundColor Green
firebase deploy --only functions:checkSubscriptionExpiry

Write-Host "`n12. checkSubscriptionExpiryScheduled" -ForegroundColor Green
firebase deploy --only functions:checkSubscriptionExpiryScheduled

Write-Host "`n13. checkTrialExpiryScheduled" -ForegroundColor Green
firebase deploy --only functions:checkTrialExpiryScheduled

Write-Host "`n14. adminCleanupUserTokensBatch" -ForegroundColor Green
firebase deploy --only functions:adminCleanupUserTokensBatch

Write-Host "`n15. adminCleanupUserTokensHttp" -ForegroundColor Green
firebase deploy --only functions:adminCleanupUserTokensHttp

Write-Host "`n16. cleanupOldTokens" -ForegroundColor Green
firebase deploy --only functions:cleanupOldTokens

Write-Host "`n17. cleanupUserTokens" -ForegroundColor Green
firebase deploy --only functions:cleanupUserTokens

Write-Host "`n18. fixExpiredSubscriptions" -ForegroundColor Green
firebase deploy --only functions:fixExpiredSubscriptions

Write-Host "`n19. reconcileSubscriptions" -ForegroundColor Green
firebase deploy --only functions:reconcileSubscriptions

Write-Host "`n20. handlePlayRtdn" -ForegroundColor Green
firebase deploy --only functions:handlePlayRtdn

Write-Host "`n=== Deploy befejezve ===" -ForegroundColor Cyan



