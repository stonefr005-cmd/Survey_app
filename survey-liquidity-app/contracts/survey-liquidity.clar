;; Survey Liquidity Pools for incentivized survey campaigns
;; Sponsors deposit STX liquidity into per-campaign pools.
;; Respondents can claim fixed rewards once per campaign.

(define-data-var next-campaign-id uint u0)

(define-map campaigns
  { id: uint }
  {
    owner: principal,
    reward-per-response: uint,
    total-deposited: uint,
    total-claimed: uint,
    active: bool
  }
)

(define-map claims
  { id: uint, user: principal }
  { claimed: bool }
)

(define-constant ERR-CAMPAIGN-NOT-FOUND (err u100))
(define-constant ERR-NOT-OWNER (err u101))
(define-constant ERR-CAMPAIGN-INACTIVE (err u102))
(define-constant ERR-ALREADY-CLAIMED (err u103))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u104))
(define-constant ERR-INVALID-PARAMS (err u105))

(define-read-only (get-next-campaign-id)
  (ok (var-get next-campaign-id))
)

(define-read-only (get-campaign (id uint))
  (match (map-get? campaigns { id: id })
    campaign (ok campaign)
    ERR-CAMPAIGN-NOT-FOUND
  )
)

(define-read-only (get-claim-status (id uint) (user principal))
  (ok (is-some (map-get? claims { id: id, user: user })))
)

(define-read-only (get-unclaimed-balance (id uint))
  (match (map-get? campaigns { id: id })
    campaign
      (let ((unclaimed (- (get total-deposited campaign) (get total-claimed campaign))))
        (ok unclaimed)
      )
    ERR-CAMPAIGN-NOT-FOUND
  )
)

;; Create a new survey campaign with an initial STX liquidity deposit.
(define-public (create-campaign (reward-per-response uint) (initial-liquidity uint))
  (if (or (<= reward-per-response u0) (< initial-liquidity reward-per-response))
      ERR-INVALID-PARAMS
      (let (
        (campaign-id (var-get next-campaign-id))
        (sender tx-sender)
      )
        (begin
          (try! (stx-transfer? initial-liquidity tx-sender (as-contract tx-sender)))
          (map-set campaigns { id: campaign-id }
            {
              owner: sender,
              reward-per-response: reward-per-response,
              total-deposited: initial-liquidity,
              total-claimed: u0,
              active: true
            }
          )
          (var-set next-campaign-id (+ campaign-id u1))
          (ok campaign-id)
        )
      )
  )
)

;; Deposit additional STX liquidity into an existing active campaign.
(define-public (deposit-liquidity (id uint) (amount uint))
  (if (is-eq amount u0)
      ERR-INVALID-PARAMS
      (match (map-get? campaigns { id: id })
        campaign
          (if (not (get active campaign))
              ERR-CAMPAIGN-INACTIVE
              (let ((sender tx-sender))
                (begin
                  (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                  (map-set campaigns { id: id }
                    {
                      owner: (get owner campaign),
                      reward-per-response: (get reward-per-response campaign),
                      total-deposited: (+ (get total-deposited campaign) amount),
                      total-claimed: (get total-claimed campaign),
                      active: true
                    }
                  )
                  (ok amount)
                )
              )
          )
        ERR-CAMPAIGN-NOT-FOUND
      )
  )
)

;; Claim a single survey reward from a funded campaign.
(define-public (claim-reward (id uint))
  (match (map-get? campaigns { id: id })
    campaign
      (if (not (get active campaign))
          ERR-CAMPAIGN-INACTIVE
          (let (
            (user tx-sender)
            (reward (get reward-per-response campaign))
            (unclaimed (- (get total-deposited campaign) (get total-claimed campaign)))
          )
            (if (is-some (map-get? claims { id: id, user: user }))
                ERR-ALREADY-CLAIMED
                (if (< unclaimed reward)
                    ERR-INSUFFICIENT-LIQUIDITY
                    (begin
                      (map-set claims { id: id, user: user } { claimed: true })
                      (map-set campaigns { id: id }
                        {
                          owner: (get owner campaign),
                          reward-per-response: reward,
                          total-deposited: (get total-deposited campaign),
                          total-claimed: (+ (get total-claimed campaign) reward),
                          active: true
                        }
                      )
                      (try! (as-contract (stx-transfer? reward tx-sender user)))
                      (ok reward)
                    )
                )
            )
          )
      )
    ERR-CAMPAIGN-NOT-FOUND
  )
)

;; Close a campaign and return any unclaimed liquidity to the owner.
(define-public (close-campaign (id uint))
  (match (map-get? campaigns { id: id })
    campaign
      (let ((caller tx-sender))
        (if (is-eq caller (get owner campaign))
            (let ((unclaimed (- (get total-deposited campaign) (get total-claimed campaign))))
              (begin
                (map-set campaigns { id: id }
                  {
                    owner: (get owner campaign),
                    reward-per-response: (get reward-per-response campaign),
                    total-deposited: (get total-deposited campaign),
                    total-claimed: (get total-claimed campaign),
                    active: false
                  }
                )
                (if (> unclaimed u0)
                    (begin
                      (try! (as-contract (stx-transfer? unclaimed tx-sender caller)))
                      (ok unclaimed)
                    )
                    (ok u0)
                )
              )
            )
            ERR-NOT-OWNER
        )
      )
    ERR-CAMPAIGN-NOT-FOUND
  )
)
