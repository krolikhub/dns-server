variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_public_key_content" {
  description = "Direct SSH public key content (alternative to ssh_public_key_path)"
  type        = string
  default     = ""
}

variable "ubuntu_password" {
  description = "Пароль для пользователя ubuntu (для SSH доступа по паролю)"
  type        = string
  default     = "ubuntu"
  sensitive   = true
}
