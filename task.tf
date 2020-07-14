provider "aws" {
  region = "ap-south-1"
  profile = "anuddeeph" 
}

#create key
resource "tls_private_key" "key_create"  {
  algorithm = "RSA"
}
resource "aws_key_pair" "taskkey" {
  key_name    = "taskkey"
  public_key = tls_private_key.key_create.public_key_openssh
  }
resource "local_file" "save_key" {
    content     = tls_private_key.key_create.private_key_pem
    filename = "taskkey.pem"
}

#create security_groups
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-09bfa361"
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }


  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "tasksg"
  }

}
variable "enter_ur_key_name" {
		type = string
    	default = "taskkey"
}

#create instance
resource "aws_instance" "webapp" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = var.enter_ur_key_name
  security_groups = [ "allow_http" ]
 
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =  tls_private_key.key_create.private_key_pem
    host     = aws_instance.webapp.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y httpd git php",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]
  }
tags = {
    Name = "webserver"
  }
}

#create EBS
resource "aws_ebs_volume" "ebs" {
  availability_zone = aws_instance.webapp.availability_zone
  size              = 1
  tags = {
    Name = "task_ebs"
  }
}

#create attachment
resource "aws_volume_attachment" "ebs-attach" {
  device_name = "/dev/sdh"
  volume_id    = "${aws_ebs_volume.ebs.id}"
  instance_id  = "${aws_instance.webapp.id}"
  force_detach = true
}
output "myoutaz" {
		value = aws_instance.webapp.availability_zone
}		
output "myoutip" {
		value = aws_instance.webapp.public_ip
} 

resource "null_resource" "save_ip" {
  provisioner "local-exec" {
    command = "echo ${aws_instance.webapp.public_ip} >> public_ip.txt"
  }
}

#mount
resource "null_resource" "null_vol_attach"  {
  depends_on = [
    aws_volume_attachment.ebs-attach,
  ]
 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key_create.private_key_pem
    host     = aws_instance.webapp.public_ip
  }


provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Anuddeeph/HMCTask.git /var/www/html/"
    ]
  }
}
resource "null_resource" "null_vol_depend"  {


depends_on = [
    null_resource.null_vol_attach,
  ]
}

#To create S3 bucket
resource "aws_s3_bucket" "my-terra-task-bucket" {
  bucket = "my-terra-task-bucket"
  acl    = "public-read"
  force_destroy  = true
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://my-terra-task-bucket"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
depends_on = [
   aws_volume_attachment.ebs-attach,
  ]
}
resource "aws_s3_bucket_object" "obj" {
  key = "ironman.jpg"
  bucket = aws_s3_bucket.my-terra-task-bucket.id
  source = "ironman.jpg"
  acl="public-read"
}

# Create Cloudfront distribution
resource "aws_cloudfront_distribution" "distribution_s3" {
    origin {
        domain_name = "${aws_s3_bucket.my-terra-task-bucket.bucket_regional_domain_name}"
        origin_id = "S3-${aws_s3_bucket.my-terra-task-bucket.bucket}"


        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
}
    # By default, show ironman.jpg file
    default_root_object = "ironman.jpg"
    enabled = true


    # If there is a 404, return ironman.jpg with a HTTP 200 Response
    custom_error_response {
        error_caching_min_ttl = 3000
        error_code = 404
        response_code = 200
        response_page_path = "/ironman.jpg"
    }


    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.my-terra-task-bucket.bucket}"


        #Not Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false
	    cookies {
		forward = "none"
	    }
            
        }


        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }


    # Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }


    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}
output "cloudfront_ip_addr" {
  value = aws_cloudfront_distribution.distribution_s3.domain_name
}
 resource "null_resource" "nullloc"  {
 depends_on = [
 null_resource.null_vol_attach,aws_cloudfront_distribution.distribution_s3,aws_s3_bucket.my-terra-task-bucket,
 ]
	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.webapp.public_ip}"
  	}
}