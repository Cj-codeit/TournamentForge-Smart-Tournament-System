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