;; TournamentForge - Smart Contract Tournament Management System
;; Handles bracket creation, prize pools, and automatic payouts

(define-fungible-token prize-token)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-tournament-not-found (err u101))
(define-constant err-not-registered (err u102))
(define-constant err-tournament-full (err u103))
(define-constant err-insufficient-entry-fee (err u104))
(define-constant err-tournament-started (err u105))
(define-constant err-invalid-result (err u106))
(define-constant err-unauthorized (err u107))
(define-constant err-invalid-round (err u108))
(define-constant err-match-not-ready (err u109))
(define-constant err-insufficient-balance (err u110))

(define-data-var next-tournament-id uint u1)
(define-data-var next-match-id uint u1)
(define-data-var platform-fee-rate uint u5) ;; 5% platform fee

(define-map tournaments
  { tournament-id: uint }
  {
    tournament-name: (string-ascii 50),
    organizer: principal,
    game-title: (string-ascii 50),
    max-participants: uint,
    current-participants: uint,
    entry-fee: uint,
    total-prize-pool: uint,
    tournament-type: (string-ascii 20),
    status: (string-ascii 20),
    start-time: uint,
    registration-deadline: uint,
    winner: (optional principal)
  })

(define-map tournament-participants
  { tournament-id: uint, player: principal }
  {
    registration-time: uint,
    entry-fee-paid: uint,
    current-round: uint,
    is-eliminated: bool,
    final-position: uint
  })

(define-map tournament-matches
  { match-id: uint }
  {
    tournament-id: uint,
    round-number: uint,
    player1: principal,
    player2: principal,
    winner: (optional principal),
    match-status: (string-ascii 20),
    match-time: uint,
    result-submitted: bool
  })

(define-map prize-distribution
  { tournament-id: uint, position: uint }
  { prize-amount: uint, claimed: bool })

(define-map tournament-brackets
  { tournament-id: uint }
  {
    total-rounds: uint,
    current-round: uint,
    matches-per-round: uint,
    bracket-type: (string-ascii 20)
  })

;; New data structures for enhanced functionality
(define-map round-schedules
  { tournament-id: uint, round-number: uint }
  {
    scheduled-start-time: uint,
    duration-minutes: uint,
    matches-completed: uint,
    total-matches: uint,
    round-status: (string-ascii 20)
  })

(define-map player-statistics
  { player: principal }
  {
    tournaments-played: uint,
    tournaments-won: uint,
    total-earnings: uint,
    win-rate: uint,
    average-placement: uint
  })

(define-map sponsor-contributions
  { tournament-id: uint, sponsor: principal }
  {
    contribution-amount: uint,
    sponsor-benefits: (string-ascii 100),
    contribution-time: uint
  })

  (define-public (create-tournament
  (tournament-name (string-ascii 50))
  (game-title (string-ascii 50))
  (max-participants uint)
  (entry-fee uint)
  (tournament-type (string-ascii 20))
  (start-time uint)
  (registration-deadline uint))
  (let 
    ((tournament-id (var-get next-tournament-id))
     (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1)))))
    (begin
      (map-set tournaments { tournament-id: tournament-id }
        {
          tournament-name: tournament-name,
          organizer: tx-sender,
          game-title: game-title,
          max-participants: max-participants,
          current-participants: u0,
          entry-fee: entry-fee,
          total-prize-pool: u0,
          tournament-type: tournament-type,
          status: "registration",
          start-time: start-time,
          registration-deadline: registration-deadline,
          winner: none
        })
      
      ;; Initialize prize distribution (example: 50% winner, 30% runner-up, 20% third)
      (map-set prize-distribution { tournament-id: tournament-id, position: u1 } 
        { prize-amount: u0, claimed: false })
      (map-set prize-distribution { tournament-id: tournament-id, position: u2 } 
        { prize-amount: u0, claimed: false })
      (map-set prize-distribution { tournament-id: tournament-id, position: u3 } 
        { prize-amount: u0, claimed: false })
      
      (var-set next-tournament-id (+ tournament-id u1))
      (ok tournament-id))))

(define-public (register-for-tournament (tournament-id uint))
  (let 
    ((tournament-info (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-tournament-not-found))
     (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1)))))
    (begin
      (asserts! (is-eq (get status tournament-info) "registration") err-tournament-started)
      (asserts! (< (get current-participants tournament-info) (get max-participants tournament-info)) err-tournament-full)
      (asserts! (< current-time (get registration-deadline tournament-info)) err-tournament-started)
      (asserts! (is-none (map-get? tournament-participants { tournament-id: tournament-id, player: tx-sender })) err-not-registered)
      
      ;; Transfer entry fee (if required)
      (if (> (get entry-fee tournament-info) u0)
        (try! (ft-transfer? prize-token (get entry-fee tournament-info) tx-sender (get organizer tournament-info)))
        true)
      
      ;; Register participant
      (map-set tournament-participants { tournament-id: tournament-id, player: tx-sender }
        {
          registration-time: current-time,
          entry-fee-paid: (get entry-fee tournament-info),
          current-round: u1,
          is-eliminated: false,
          final-position: u0
        })
      
      ;; Update tournament stats
      (let ((updated-prize-pool (+ (get total-prize-pool tournament-info) (get entry-fee tournament-info))))
        (map-set tournaments { tournament-id: tournament-id }
          (merge tournament-info {
            current-participants: (+ (get current-participants tournament-info) u1),
            total-prize-pool: updated-prize-pool
          })))
      
      (ok true))))

(define-public (start-tournament (tournament-id uint))
  (let 
    ((tournament-info (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-tournament-not-found))
     (participant-count (get current-participants tournament-info))
     (total-rounds (calculate-tournament-rounds participant-count)))
    (begin
      (asserts! (is-eq tx-sender (get organizer tournament-info)) err-unauthorized)
      (asserts! (is-eq (get status tournament-info) "registration") err-tournament-started)
      (asserts! (>= participant-count u2) err-insufficient-entry-fee)
      
      ;; Update tournament status
      (map-set tournaments { tournament-id: tournament-id }
        (merge tournament-info { status: "active" }))
      
      ;; Initialize bracket
      (map-set tournament-brackets { tournament-id: tournament-id }
        {
          total-rounds: total-rounds,
          current-round: u1,
          matches-per-round: (/ participant-count u2),
          bracket-type: "single-elimination"
        })
      
      ;; Update prize distribution based on total prize pool
      (let ((total-prize (get total-prize-pool tournament-info)))
        (begin
          (map-set prize-distribution { tournament-id: tournament-id, position: u1 }
            { prize-amount: (/ (* total-prize u50) u100), claimed: false })
          (map-set prize-distribution { tournament-id: tournament-id, position: u2 }
            { prize-amount: (/ (* total-prize u30) u100), claimed: false })
          (map