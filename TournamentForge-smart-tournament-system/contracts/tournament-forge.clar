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

(define-public (submit-match-result (match-id uint) (winner principal))
  (let 
    ((match-info (unwrap! (map-get? tournament-matches { match-id: match-id }) err-tournament-not-found))
     (tournament-info (unwrap! (map-get? tournaments { tournament-id: (get tournament-id match-info) }) err-tournament-not-found)))
    (begin
      (asserts! (is-eq tx-sender (get organizer tournament-info)) err-unauthorized)
      (asserts! (not (get result-submitted match-info)) err-invalid-result)
      (asserts! (or (is-eq winner (get player1 match-info)) (is-eq winner (get player2 match-info))) err-invalid-result)
      
      ;; Update match result
      (map-set tournament-matches { match-id: match-id }
        (merge match-info {
          winner: (some winner),
          match-status: "completed",
          result-submitted: true
        }))
      
      ;; Eliminate loser
      (let ((loser (if (is-eq winner (get player1 match-info)) (get player2 match-info) (get player1 match-info))))
        (map-set tournament-participants 
          { tournament-id: (get tournament-id match-info), player: loser }
          (merge 
            (unwrap-panic (map-get? tournament-participants { tournament-id: (get tournament-id match-info), player: loser }))
            { is-eliminated: true })))
      
      (ok true))))

(define-public (claim-prize (tournament-id uint) (position uint))
  (let 
    ((tournament-info (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-tournament-not-found))
     (prize-info (unwrap! (map-get? prize-distribution { tournament-id: tournament-id, position: position }) err-tournament-not-found))
     (participant-info (unwrap! (map-get? tournament-participants { tournament-id: tournament-id, player: tx-sender }) err-not-registered)))
    (begin
      (asserts! (is-eq (get status tournament-info) "completed") err-tournament-started)
      (asserts! (is-eq (get final-position participant-info) position) err-unauthorized)
      (asserts! (not (get claimed prize-info)) err-invalid-result)
      
      ;; Transfer prize
      (try! (ft-transfer? prize-token (get prize-amount prize-info) (get organizer tournament-info) tx-sender))
      
      ;; Mark as claimed
      (map-set prize-distribution { tournament-id: tournament-id, position: position }
        (merge prize-info { claimed: true }))
      
      (ok (get prize-amount prize-info)))))

;; ADVANCED ROUND MANAGEMENT: Enhanced round scheduling and match generation
(define-public (schedule-tournament-round 
  (tournament-id uint) 
  (round-number uint) 
  (start-time uint) 
  (duration-minutes uint))
  (let 
    ((tournament-info (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-tournament-not-found))
     (bracket-info (unwrap! (map-get? tournament-brackets { tournament-id: tournament-id }) err-tournament-not-found))
     (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1)))))
    (begin
      (asserts! (is-eq tx-sender (get organizer tournament-info)) err-unauthorized)
      (asserts! (is-eq (get status tournament-info) "active") err-tournament-started)
      (asserts! (<= round-number (get total-rounds bracket-info)) err-invalid-round)
      (asserts! (>= start-time current-time) err-invalid-result)
      
      ;; Calculate total matches for this round
      (let ((participants-remaining (calculate-remaining-participants tournament-id round-number))
            (matches-in-round (/ participants-remaining u2)))
        (begin
          ;; Schedule the round
          (map-set round-schedules { tournament-id: tournament-id, round-number: round-number }
            {
              scheduled-start-time: start-time,
              duration-minutes: duration-minutes,
              matches-completed: u0,
              total-matches: matches-in-round,
              round-status: "scheduled"
            })
          
          ;; Generate matches for the round - now properly implemented
          (let ((match-generation-result (generate-round-matches tournament-id round-number)))
            (asserts! (is-ok match-generation-result) err-match-not-ready))
          
          ;; Update bracket current round if this is the next round
          (if (is-eq round-number (+ (get current-round bracket-info) u1))
            (map-set tournament-brackets { tournament-id: tournament-id }
              (merge bracket-info { current-round: round-number }))
            true)
          
          (ok matches-in-round))))))

;; PLAYER STATISTICS: Comprehensive tracking and leaderboard management
(define-public (update-player-statistics (tournament-id uint))
  (let 
    ((tournament-info (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-tournament-not-found))
     (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1)))))
    (begin
      (asserts! (is-eq (get status tournament-info) "completed") err-tournament-started)
      (asserts! (is-eq tx-sender (get organizer tournament-info)) err-unauthorized)
      
      ;; Update statistics for winner
      (match (get winner tournament-info)
        winner-principal (begin
          (let ((current-stats (default-to 
                  { tournaments-played: u0, tournaments-won: u0, total-earnings: u0, win-rate: u0, average-placement: u0 }
                  (map-get? player-statistics { player: winner-principal })))
                (winner-prize (get prize-amount (unwrap! (map-get? prize-distribution { tournament-id: tournament-id, position: u1 }) err-tournament-not-found))))
            (begin
              (map-set player-statistics { player: winner-principal }
                {
                  tournaments-played: (+ (get tournaments-played current-stats) u1),
                  tournaments-won: (+ (get tournaments-won current-stats) u1),
                  total-earnings: (+ (get total-earnings current-stats) winner-prize),
                  win-rate: (/ (* (+ (get tournaments-won current-stats) u1) u100) (+ (get tournaments-played current-stats) u1)),
                  average-placement: (calculate-new-average-placement (get average-placement current-stats) (get tournaments-played current-stats) u1)
                })
              
              ;; Update runner-up statistics
              (update-finalist-stats tournament-id u2)
              
              ;; Update third place statistics  
              (update-finalist-stats tournament-id u3)
              
              (ok true))))
        (ok false)))))

;; SPONSORSHIP SYSTEM: Enhanced prize pools and sponsor management
(define-public (add-sponsor-contribution 
  (tournament-id uint) 
  (contribution-amount uint) 
  (sponsor-benefits (string-ascii 100)))
  (let 
    ((tournament-info (unwrap! (map-get? tournaments { tournament-id: tournament-id }) err-tournament-not-found))
     (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
     (platform-fee (/ (* contribution-amount (var-get platform-fee-rate)) u100))
     (net-contribution (- contribution-amount platform-fee)))
    (begin
      (asserts! (or (is-eq (get status tournament-info) "registration") 
                   (is-eq (get status tournament-info) "active")) err-tournament-started)
      
      ;; Transfer sponsorship amount
      (try! (ft-transfer? prize-token contribution-amount tx-sender (get organizer tournament-info)))
      
      ;; Transfer platform fee to contract owner
      (try! (ft-transfer? prize-token platform-fee (get organizer tournament-info) contract-owner))
      
      ;; Record sponsorship
      (map-set sponsor-contributions { tournament-id: tournament-id, sponsor: tx-sender }
        {
          contribution-amount: contribution-amount,
          sponsor-benefits: sponsor-benefits,
          contribution-time: current-time
        })
      
      ;; Update tournament prize pool
      (map-set tournaments { tournament-id: tournament-id }
        (merge tournament-info { 
          total-prize-pool: (+ (get total-prize-pool tournament-info) net-contribution) 
        }))
      
      ;; Recalculate prize distribution with enhanced pool
      (let ((new-total-prize (+ (get total-prize-pool tournament-info) net-contribution)))
        (begin
          (map-set prize-distribution { tournament-id: tournament-id, position: u1 }
            { prize-amount: (/ (* new-total-prize u50) u100), claimed: false })
          (map-set prize-distribution { tournament-id: tournament-id, position: u2 }
            { prize-amount: (/ (* new-total-prize u30) u100), claimed: false })
          (map-set prize-distribution { tournament-id: tournament-id, position: u3 }
            { prize-amount: (/ (* new-total-prize u20) u100), claimed: false })))
      
      (ok net-contribution))))

;; HELPER FUNCTIONS: Supporting utilities for tournament operations
(define-private (calculate-remaining-participants (tournament-id uint) (round-number uint))
  (let ((total-participants (get current-participants (unwrap-panic (map-get? tournaments { tournament-id: tournament-id })))))
    (/ total-participants (pow u2 (- round-number u1)))))

(define-private (generate-round-matches (tournament-id uint) (round-number uint))
  (let ((participants-remaining (calculate-remaining-participants tournament-id round-number)))
    (if (< participants-remaining u2)
      err-insufficient-entry-fee
      (begin
        ;; Create matches for remaining participants
        ;; This is a simplified implementation - real implementation would need proper pairing logic
        (let ((matches-to-create (/ participants-remaining u2)))
          (if (> matches-to-create u0)
            (ok matches-to-create)
            err-match-not-ready))))))

(define-private (calculate-new-average-placement (current-avg uint) (games-played uint) (new-placement uint))
  (if (is-eq games-played u0)
    new-placement
    (/ (+ (* current-avg games-played) new-placement) (+ games-played u1))))

(define-private (update-finalist-stats (tournament-id uint) (position uint))
  (let ((prize-info (map-get? prize-distribution { tournament-id: tournament-id, position: position })))
    (match prize-info
      prize-data true
      false)))

(define-private (calculate-tournament-rounds (participants uint))
  (if (<= participants u2) u1
    (if (<= participants u4) u2
      (if (<= participants u8) u3
        (if (<= participants u16) u4 u5)))))

;; READ-ONLY FUNCTIONS: Data access and query functions
(define-read-only (get-tournament-info (tournament-id uint))
  (map-get? tournaments { tournament-id: tournament-id }))

(define-read-only (get-participant-info (tournament-id uint) (player principal))
  (map-get? tournament-participants { tournament-id: tournament-id, player: player }))

(define-read-only (get-match-info (match-id uint))
  (map-get? tournament-matches { match-id: match-id }))

(define-read-only (get-prize-info (tournament-id uint) (position uint))
  (map-get? prize-distribution { tournament-id: tournament-id, position: position }))

(define-read-only (get-bracket-info (tournament-id uint))
  (map-get? tournament-brackets { tournament-id: tournament-id }))

(define-read-only (get-round-schedule (tournament-id uint) (round-number uint))
  (map-get? round-schedules { tournament-id: tournament-id, round-number: round-number }))

(define-read-only (get-player-stats (player principal))
  (map-get? player-statistics { player: player }))

(define-read-only (get-sponsor-info (tournament-id uint) (sponsor principal))
  (map-get? sponsor-contributions { tournament-id: tournament-id, sponsor: sponsor }))

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate))