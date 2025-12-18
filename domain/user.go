package domain

type User struct {
	ID        int    `json:"id" db:"id"`
	Username  string `json:"username" db:"username"`
	Email     string `json:"email" db:"email"`
	Password  string `json:"password,omitempty" db:"password"`
	Role      string `json:"role" db:"role"`
	CreatedAt string `json:"created_at,omitempty" db:"created_at"`
}
