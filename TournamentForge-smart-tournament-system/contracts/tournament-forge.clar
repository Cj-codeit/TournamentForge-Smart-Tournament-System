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