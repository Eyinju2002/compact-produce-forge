;; Compact Produce Forge: Decentralized Agricultural Investment Platform
;; This contract manages digital agricultural investment tokens, enabling fractional ownership
;; and investment in agricultural production and trade.

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PRODUCE-NOT-FOUND (err u101))
(define-constant ERR-PRODUCE-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-INVESTMENT-LIMIT (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-PRODUCE-NOT-MATURE (err u106))
(define-constant ERR-INSUFFICIENT-BALANCE (err u109))

;; Data Maps and Variables

;; Track authorized produce managers
(define-map produce-managers principal bool)

;; Produce investment structure
(define-map produce-investments 
  uint 
  {
    manager: principal,
    total-investment-target: uint,
    crop-type: (string-ascii 32),
    location: (string-ascii 64),
    investment-start: uint,
    maturity-blocks: uint,
    is-complete: bool,
    current-investment: uint
  }
)

;; Individual investor holdings
(define-map investment-holdings 
  { investment-id: uint, investor: principal } 
  uint
)

;; Investment distribution tracking
(define-map investment-distributions
  { investment-id: uint, distribution-period: uint }
  { amount: uint, is-distributed: bool }
)

;; Investment ID counter
(define-data-var next-investment-id uint u1)

;; Contract owner
(define-data-var contract-manager principal tx-sender)

;; Private Functions

;; Check if a principal is an authorized produce manager
(define-private (is-authorized-manager (manager principal))
  (default-to false (map-get? produce-managers manager))
)

;; Calculate investment returns
(define-private (calculate-investment-return (investment-id uint) (holdings uint))
  (let (
    (investment (unwrap! (map-get? produce-investments investment-id) u0))
    (total-target (get total-investment-target investment))
    (current-investment (get current-investment investment))
  )
    ;; Proportional return calculation
    (/ (* holdings current-investment) total-target)
  )
)

;; Read-only Functions

;; Retrieve produce investment details
(define-read-only (get-investment (investment-id uint))
  (map-get? produce-investments investment-id)
)

;; Get investor's investment balance
(define-read-only (get-investment-balance (investment-id uint) (investor principal))
  (ok (default-to u0 
    (map-get? investment-holdings { investment-id: investment-id, investor: investor })
  ))
)

;; Public Functions

;; Add a new authorized produce manager
(define-public (add-produce-manager (manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-manager)) ERR-UNAUTHORIZED)
    (ok (map-set produce-managers manager true))
  )
)

;; Create a new produce investment opportunity
(define-public (create-produce-investment 
  (total-investment-target uint) 
  (crop-type (string-ascii 32)) 
  (location (string-ascii 64))
  (maturity-blocks uint))
  
  (let (
    (investment-id (var-get next-investment-id))
  )
    ;; Validation checks
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> total-investment-target u0) ERR-INVALID-AMOUNT)
    (asserts! (> maturity-blocks u0) ERR-INVALID-AMOUNT)
    
    ;; Create the investment
    (map-set produce-investments 
      investment-id
      {
        manager: tx-sender,
        total-investment-target: total-investment-target,
        crop-type: crop-type,
        location: location,
        investment-start: block-height,
        maturity-blocks: maturity-blocks,
        is-complete: false,
        current-investment: u0
      }
    )
    
    ;; Increment investment ID counter
    (var-set next-investment-id (+ investment-id u1))
    
    (ok investment-id)
  )
)

;; Invest in a produce opportunity
(define-public (invest-in-produce (investment-id uint) (investment-amount uint))
  (let (
    (investment (unwrap! (map-get? produce-investments investment-id) ERR-PRODUCE-NOT-FOUND))
    (total-target (get total-investment-target investment))
    (current-investment (get current-investment investment))
    (remaining-investment (- total-target current-investment))
  )
    ;; Check investment constraints
    (asserts! (<= (+ current-investment investment-amount) total-target) ERR-INVESTMENT-LIMIT)
    (asserts! (>= (stx-get-balance tx-sender) investment-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer investment to produce manager
    (try! (stx-transfer? investment-amount tx-sender (get manager investment)))
    
    ;; Update investor's holdings
    (let (
      (current-balance (default-to u0 
        (map-get? investment-holdings { investment-id: investment-id, investor: tx-sender })
      ))
    )
      (map-set investment-holdings 
        { investment-id: investment-id, investor: tx-sender }
        (+ current-balance investment-amount)
      )
    )
    
    ;; Update total investment
    (map-set produce-investments 
      investment-id
      (merge investment { current-investment: (+ current-investment investment-amount) })
    )
    
    (ok investment-amount)
  )
)

;; Distribute investment returns
(define-public (distribute-returns (investment-id uint) (distribution-amount uint))
  (let (
    (investment (unwrap! (map-get? produce-investments investment-id) ERR-PRODUCE-NOT-FOUND))
    (manager (get manager investment))
  )
    ;; Only investment manager can distribute returns
    (asserts! (is-eq tx-sender manager) ERR-UNAUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) distribution-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer distribution to contract
    (try! (stx-transfer? distribution-amount tx-sender (as-contract tx-sender)))
    
    ;; Record distribution
    (map-set investment-distributions 
      { investment-id: investment-id, distribution-period: block-height }
      { amount: distribution-amount, is-distributed: false }
    )
    
    (ok distribution-amount)
  )
)

;; Claim investment returns
(define-public (claim-returns (investment-id uint))
  (let (
    (investment (unwrap! (map-get? produce-investments investment-id) ERR-PRODUCE-NOT-FOUND))
    (investor-holdings (default-to u0 
      (map-get? investment-holdings { investment-id: investment-id, investor: tx-sender })
    ))
    (distribution-data (unwrap! 
      (map-get? investment-distributions { investment-id: investment-id, distribution-period: block-height }) 
      ERR-PRODUCE-NOT-MATURE
    ))
  )
    ;; Investor must have holdings
    (asserts! (> investor-holdings u0) ERR-INSUFFICIENT-BALANCE)
    
    ;; Calculate proportional returns
    (let (
      (total-return (get amount distribution-data))
      (investor-return (calculate-investment-return investment-id investor-holdings))
    )
      ;; Transfer returns to investor
      (try! (as-contract (stx-transfer? investor-return tx-sender tx-sender)))
      
      ;; Mark distribution as complete for this investor
      (map-set investment-distributions 
        { investment-id: investment-id, distribution-period: block-height }
        (merge distribution-data { is-distributed: true })
      )
      
      (ok investor-return)
    )
  )
)

;; Transfer contract management
(define-public (transfer-contract-management (new-manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-manager)) ERR-UNAUTHORIZED)
    (var-set contract-manager new-manager)
    (ok true)
  )
)